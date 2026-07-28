import Foundation

public enum StatusPaths {
    public static let appBundleIdentifier = "com.felixtorres.agentmeter"

    public static var snapshotFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentMeter/status.json", isDirectory: false)
    }
}
