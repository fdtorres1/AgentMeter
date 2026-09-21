import Foundation

/// Opt-in stderr tracing for development only (`AGENTMETER_DEBUG=1`).
/// Never logs credentials; callers must pass only structural information.
enum DebugLog {
    nonisolated private static let enabled =
        ProcessInfo.processInfo.environment["AGENTMETER_DEBUG"] != nil

    nonisolated static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[AgentMeter] \(message())\n".utf8))
    }
}
