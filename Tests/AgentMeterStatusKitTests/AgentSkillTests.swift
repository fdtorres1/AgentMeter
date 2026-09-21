import XCTest
import AgentMeterStatusKit

final class AgentSkillTests: XCTestCase {
    func testMarkdownMatchesDocsAgentSkillFile() throws {
        let repoRoot = try locateRepoRoot()
        let skillFileURL = repoRoot.appendingPathComponent("docs/agent-skill/SKILL.md")
        let fileData = try Data(contentsOf: skillFileURL)
        let embeddedData = Data(AgentSkill.markdown.utf8)
        XCTAssertEqual(
            embeddedData,
            fileData,
            "AgentSkill.markdown is out of sync with docs/agent-skill/SKILL.md — update both to match."
        )
    }

    private func locateRepoRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while directory.path != "/" {
            let packageURL = directory.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageURL.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "AgentSkillTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root from test file path."]
        )
    }
}
