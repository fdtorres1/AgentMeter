import AppKit
import Foundation

enum CLIToolInstaller {
    static let homebrewPath = "/opt/homebrew/bin/agentmeter"
    static let localPath = "/usr/local/bin/agentmeter"

    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var bundledHelperPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/agentmeter")
            .path
    }

    static func detectedInstallPath() -> String? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: homebrewPath) {
            return homebrewPath
        }
        if fileManager.fileExists(atPath: localPath) {
            return localPath
        }
        return nil
    }

    static func isInstalledAtLocalPath() -> Bool {
        FileManager.default.fileExists(atPath: localPath)
    }

    static func install() -> Result<Void, Error> {
        let sourcePath = bundledHelperPath
        let destinationURL = URL(fileURLWithPath: localPath)
        let destinationDirectoryURL = URL(fileURLWithPath: "/usr/local/bin")
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destinationDirectoryURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue,
           fileManager.isWritableFile(atPath: destinationDirectoryURL.path) {
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                    guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
                        return installWithAdminPrivileges(sourcePath: sourcePath)
                    }
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.createSymbolicLink(
                    at: destinationURL,
                    withDestinationURL: URL(fileURLWithPath: sourcePath)
                )
                return .success(())
            } catch {
                return installWithAdminPrivileges(sourcePath: sourcePath)
            }
        }

        return installWithAdminPrivileges(sourcePath: sourcePath)
    }

    private static func installWithAdminPrivileges(sourcePath: String) -> Result<Void, Error> {
        // Two quoting layers: shell-quote the path, then escape for the
        // AppleScript string literal (the app may live in an oddly named folder).
        let quotedSource = appleScriptStringEscape(shellQuote(sourcePath))
        let scriptSource = """
        do shell script "mkdir -p /usr/local/bin && ln -sf \(quotedSource) /usr/local/bin/agentmeter" with administrator privileges
        """
        var error: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        script?.executeAndReturnError(&error)

        if let error {
            let nsError = error as? [String: Any]
            let code = nsError?[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 {
                return .failure(CancellationError())
            }
            let message = nsError?[NSAppleScript.errorMessage] as? String ?? "unknown error"
            return .failure(NSError(domain: "CLIToolInstaller", code: code, userInfo: [
                NSLocalizedDescriptionKey: message,
            ]))
        }

        return .success(())
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptStringEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
