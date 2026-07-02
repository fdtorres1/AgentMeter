import Foundation
import Combine

/// Holds the latest usage for all providers and refreshes them on a timer,
/// plus a file watcher so Codex numbers update right after CLI activity.
@MainActor
final class UsageStore: ObservableObject {
    /// Per-provider state, keyed by provider id.
    @Published private(set) var states: [String: ProviderState] = [:]
    @Published var lastRefreshed: Date?

    let providers: [any UsageProvider]
    let settings: SettingsStore

    private let codexReader = CodexUsageReader()
    private var timer: Timer?
    private var sessionWatcher: DispatchSourceFileSystemObject?
    private var watchedFile: URL?

    init(settings: SettingsStore, providers: [any UsageProvider] = UsageStore.defaultProviders) {
        self.settings = settings
        self.providers = providers
        for provider in providers {
            states[provider.id] = .loading
        }
        refresh()
        rescheduleTimer()
    }

    nonisolated static var defaultProviders: [any UsageProvider] {
        [CodexProvider(), CursorProvider(), ClaudeProvider(), GeminiProvider()]
    }

    deinit {
        timer?.invalidate()
        sessionWatcher?.cancel()
    }

    func rescheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: settings.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
        } catch {
            states[provider.id] = .error(error.localizedDescription)
        }
    }

    /// Menu bar text, e.g. "Cx 5% · Cu 20%". Only visible providers appear.
    var menuBarTitle: String {
        let visible = visibleProviders
        guard !visible.isEmpty else { return "AgentMeter" }
        return visible.map { provider in
            switch state(for: provider.id) {
            case .loading: return "\(provider.shortCode) …"
            case .error: return "\(provider.shortCode) !"
            case .ready(let usage):
                guard let worst = usage.worstWindow else { return "\(provider.shortCode) ?" }
                return "\(provider.shortCode) \(Int(worst.usedPercent.rounded()))%"
            }
        }.joined(separator: " · ")
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
