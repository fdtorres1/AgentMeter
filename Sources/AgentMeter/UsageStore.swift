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
            states[provider.id] = .error(error.localizedDescription)
        }
    }

    /// Menu bar text, e.g. "Cx 5% · Cu 20%". Only visible providers with menu-bar
    /// visibility appear; compact mode shows the single most constrained entry.
    var menuBarTitle: String {
        let titleProviders = visibleProviders.filter { settings.showsInMenuBar($0.id) }
        guard !titleProviders.isEmpty else { return "AgentMeter" }

        if settings.compactMenuBar {
            return compactMenuBarTitle(for: titleProviders)
        }

        return titleProviders.map { providerEntry(for: $0) }.joined(separator: " · ")
    }

    private func compactMenuBarTitle(for providers: [any UsageProvider]) -> String {
        var bestPercent: (provider: any UsageProvider, used: Double)?
        var firstBalance: (provider: any UsageProvider, usage: ProviderUsage)?

        for provider in providers {
            guard case .ready(let usage) = state(for: provider.id) else { continue }
            if let worst = usage.worstWindow {
                if bestPercent == nil || worst.usedPercent > bestPercent!.used {
                    bestPercent = (provider, worst.usedPercent)
                }
            } else if usage.balance != nil, firstBalance == nil {
                firstBalance = (provider, usage)
            }
        }

        if let best = bestPercent {
            return providerEntry(for: best.provider)
        }
        if let balance = firstBalance {
            return providerEntry(for: balance.provider)
        }

        return providers.map { providerEntry(for: $0) }.joined(separator: " · ")
    }

    private func providerEntry(for provider: any UsageProvider) -> String {
        switch state(for: provider.id) {
        case .loading: return "\(provider.shortCode) …"
        case .error: return "\(provider.shortCode) !"
        case .ready(let usage):
            guard let summary = usage.menuSummary(direction: settings.countDirection) else {
                return "\(provider.shortCode) ?"
            }
            return "\(provider.shortCode) \(summary)"
        }
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
