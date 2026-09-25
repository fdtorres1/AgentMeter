import Foundation
import XCTest
@testable import AgentMeter

final class CodexAppServerClientTests: XCTestCase {
    func testConcurrentExecutableResolutionAndReset() {
        CodexAppServerClient.resetExecutableCache()
        let expected = CodexAppServerClient.resolveCodexExecutable()?.path
        let mismatchLock = NSLock()
        var mismatches = 0

        DispatchQueue.concurrentPerform(iterations: 256) { index in
            if index.isMultiple(of: 8) {
                CodexAppServerClient.resetExecutableCache()
            }
            let actual = CodexAppServerClient.resolveCodexExecutable()?.path
            if actual != expected {
                mismatchLock.withLock { mismatches += 1 }
            }
        }

        XCTAssertEqual(mismatches, 0)
        XCTAssertEqual(CodexAppServerClient.resolveCodexExecutable()?.path, expected)
    }
}
