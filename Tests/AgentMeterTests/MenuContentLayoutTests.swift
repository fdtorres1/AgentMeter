import AppKit
import SwiftUI
import XCTest
@testable import AgentMeter

final class MenuContentLayoutTests: XCTestCase {
    @MainActor
    func testShortMenuStaysCompactAndLongMenuScrolls() async throws {
        let short = await makeMenu(providerCount: 1)
        let long = await makeMenu(providerCount: 16)
        defer {
            short.window.close()
            long.window.close()
        }

        XCTAssertLessThan(short.host.fittingSize.height, 350)
        XCTAssertLessThan(long.host.fittingSize.height, 800)
        XCTAssertGreaterThan(long.host.fittingSize.height, short.host.fittingSize.height)

        let scroll = try XCTUnwrap(findScrollView(in: long.host))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
        let viewport = long.host.convert(scroll.bounds, from: scroll)
        // Space outside the scroll viewport keeps the footer reachable.
        XCTAssertGreaterThan(long.host.bounds.height - viewport.height, 50)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
        XCTAssertEqual(long.host.convert(scroll.bounds, from: scroll), viewport)
    }

    @MainActor
    private func makeMenu(providerCount: Int) async -> (host: NSHostingView<MenuContent>, window: NSWindow) {
        _ = NSApplication.shared
        let suite = "MenuContentLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        settings.resetTimeStyle = .absolute
        settings.setMode(.off, for: "codex")
        let providers = (0..<providerCount).map { LayoutProvider(id: "layout-\($0)") }
        let store = UsageStore(settings: settings, providers: providers)
        let host = NSHostingView(rootView: MenuContent(store: store, settings: settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 750),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        // Allow provider completion and SwiftUI preferences to settle without
        // showing a window or using the user's settings, credentials, or APIs.
        for _ in 0..<8 {
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        defaults.removePersistentDomain(forName: suite)
        return (host, window)
    }

    @MainActor
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}

private struct LayoutProvider: UsageProvider {
    let id: String
    var displayName: String { "Test provider" }
    var shortCode: String { "T" }
    var isDetected: Bool { true }
    func fetch() async throws -> ProviderUsage {
        ProviderUsage(planName: "Test", windows: [
            UsageWindow(label: "Weekly limit", usedPercent: 25,
                        resetsAt: Date().addingTimeInterval(6 * 86400 + 11 * 3600))
        ], asOf: Date())
    }
}
