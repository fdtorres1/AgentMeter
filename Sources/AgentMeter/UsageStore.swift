import Foundation
import Combine
import AppKit

/// Holds the latest usage for all providers and refreshes them on a timer,
/// plus a file watcher so Codex numbers update right after CLI activity.
@MainActor
final class UsageStore: ObservableObject {
    /// Per-provider state, keyed by provider id.
    @Published private(set) var states: [String: ProviderState] = [:]
    @Published var lastRefreshed: Date?

    let providers: [any UsageProvider]
    let settings: SettingsStore
    lazy var notificationManager = NotificationManager()

    private let codexReader = CodexUsageReader()
    private var timer: Timer?
    private var sessionWatcher: DispatchSourceFileSystemObject?
    private var watchedFile: URL?

    private var credentialsObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(settings: SettingsStore, providers: [any UsageProvider] = UsageStore.defaultProviders) {
        self.settings = settings
        self.providers = providers
        for provider in providers {
            states[provider.id] = .loading
        }
        refresh()
        rescheduleTimer()
        credentialsObserver = NotificationCenter.default.addObserver(
            forName: .providerCredentialsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    nonisolated static var defaultProviders: [any UsageProvider] {
        [
            CodexProvider(), CursorProvider(), ClaudeProvider(), GeminiProvider(),
            OpenRouterProvider(), DeepSeekProvider(), MoonshotProvider(),
            ZaiProvider(), VeniceProvider(),
        ]
    }

    deinit {
        timer?.invalidate()
        sessionWatcher?.cancel()
        if let credentialsObserver {
            NotificationCenter.default.removeObserver(credentialsObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func rescheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: settings.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    /// Providers currently visible per settings (mode + detection).
    var visibleProviders: [any UsageProvider] {
        providers.filter { settings.mode(for: $0.id).isVisible(detected: $0.isDetected) }
    }

    func state(for providerID: String) -> ProviderState {
        states[providerID] ?? .loading
    }

    func refresh() {
        for provider in visibleProviders {
            Task { await refreshProvider(provider) }
        }
        watchNewestCodexSession()
        lastRefreshed = Date()
    }

    private func refreshProvider(_ provider: any UsageProvider) async {
        do {
            let usage = try await provider.fetch()
            states[provider.id] = .ready(usage)
            notificationManager.notifyIfNeeded(
                provider: provider,
                usage: usage,
                settings: settings
            )
        } catch {
            let previous = states[provider.id] ?? .loading
            states[provider.id] = ProviderState.nextState(
                after: previous,
                failure: error.localizedDescription,
                at: Date()
            )
        }
    }

    private var titleProviders: [any UsageProvider] {
        visibleProviders.filter { settings.showsInMenuBar($0.id) }
    }

    /// Colored menu bar segments with per-provider severity.
    var menuBarEntries: [(text: String, severity: MenuBarSeverity)] {
        let providers = titleProviders
        guard !providers.isEmpty else { return [("AgentMeter", .normal)] }

        switch settings.menuBarStyle {
        case .full:
            return providers.map { providerMenuBarEntry(for: $0) }
        case .compact:
            if let entry = mostConstrainedMenuBarEntry(from: providers) {
                return [entry]
            }
            return providers.map { providerMenuBarEntry(for: $0) }
        case .icon:
            return []
        }
    }

    /// Worst severity across title providers (for icon-only menu bar style).
    var worstMenuBarSeverity: MenuBarSeverity {
        let providers = titleProviders
        guard !providers.isEmpty else { return .normal }

        let severities = providers.map {
            MenuBarTitleRenderer.severity(
                for: state(for: $0.id),
                balanceThreshold: settings.balanceNotificationThreshold
            )
        }
        return Self.worstSeverity(severities)
    }

    /// Menu bar text, e.g. "Cx 5% · Cu 20%". Only visible providers with menu-bar
    /// visibility appear; compact mode shows the single most constrained entry.
    var menuBarTitle: String {
        menuBarEntries.map(\.text).joined(separator: " · ")
    }

    /// Spoken summary for the raster menu bar title (VoiceOver).
    var menuBarAccessibilityDescription: String {
        MenuBarAccessibilitySummary.build(
            providers: menuBarSummaryProviders.map {
                MenuBarAccessibilitySummary.ProviderInput(
                    displayName: $0.displayName,
                    state: state(for: $0.id)
                )
            },
            countDirection: settings.countDirection,
            balanceThreshold: settings.balanceNotificationThreshold
        )
    }

    /// Providers included in the spoken menu bar summary (icon mode always lists all).
    private var menuBarSummaryProviders: [any UsageProvider] {
        let providers = titleProviders
        guard !providers.isEmpty else { return [] }

        switch settings.menuBarStyle {
        case .full, .icon:
            return providers
        case .compact:
            if let provider = mostConstrainedMenuBarProvider(from: providers) {
                return [provider]
            }
            return providers
        }
    }

    private func providerMenuBarEntry(for provider: any UsageProvider) -> (text: String, severity: MenuBarSeverity) {
        let providerState = state(for: provider.id)
        return (
            providerEntryText(for: provider, state: providerState),
            MenuBarTitleRenderer.severity(
                for: providerState,
                balanceThreshold: settings.balanceNotificationThreshold
            )
        )
    }

    private func providerEntryText(for provider: any UsageProvider, state: ProviderState) -> String {
        switch state {
        case .loading:
            return "\(provider.shortCode) …"
        case .error:
            return "\(provider.shortCode) !"
        case .ready(let usage), .stale(let usage, _, _):
            guard let summary = usage.menuSummary(direction: settings.countDirection) else {
                return "\(provider.shortCode) ?"
            }
            return "\(provider.shortCode) \(summary)"
        }
    }

    private func mostConstrainedMenuBarProvider(
        from providers: [any UsageProvider]
    ) -> (any UsageProvider)? {
        var bestPercent: (provider: any UsageProvider, used: Double)?
        var firstBalance: (provider: any UsageProvider, usage: ProviderUsage)?

        for provider in providers {
            guard let usage = state(for: provider.id).usage else { continue }
            if let worst = usage.worstWindow {
                if bestPercent == nil || worst.usedPercent > bestPercent!.used {
                    bestPercent = (provider, worst.usedPercent)
                }
            } else if usage.balance != nil, firstBalance == nil {
                firstBalance = (provider, usage)
            }
        }

        if let best = bestPercent {
            return best.provider
        }
        if let balance = firstBalance {
            return balance.provider
        }
        return nil
    }

    private func mostConstrainedMenuBarEntry(
        from providers: [any UsageProvider]
    ) -> (text: String, severity: MenuBarSeverity)? {
        guard let provider = mostConstrainedMenuBarProvider(from: providers) else { return nil }
        return providerMenuBarEntry(for: provider)
    }

    nonisolated private static func worstSeverity(_ severities: [MenuBarSeverity]) -> MenuBarSeverity {
        let rank: (MenuBarSeverity) -> Int = { severity in
            switch severity {
            case .critical: return 3
            case .warning: return 2
            case .stale: return 1
            case .normal: return 0
            }
        }
        return severities.max(by: { rank($0) < rank($1) }) ?? .normal
    }

    // MARK: - Codex session file watching

    /// Watches the newest rollout file so appended token_count events update the
    /// Codex meter immediately, without waiting for the next timer tick.
    private func watchNewestCodexSession() {
        guard settings.mode(for: "codex").isVisible(detected: CodexProvider().isDetected),
              let newest = codexReader.recentSessionFiles(limit: 1).first,
              newest != watchedFile else {
            return
        }

        sessionWatcher?.cancel()
        sessionWatcher = nil
        watchedFile = nil

        let descriptor = open(newest.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.refreshProvider(CodexProvider()) }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sessionWatcher = source
        watchedFile = newest
    }
}
