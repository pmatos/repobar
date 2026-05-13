import Foundation
@testable import repobarcli
import Testing

@Suite
struct LoginPromptTests {
    @Test
    func `interactive with noBrowser true prints URL on two lines and does not throw`() throws {
        let capture = LineCapture()
        let prompt = LoginPrompt.interactive(noBrowser: true) { capture.append($0) }

        try prompt.openURL(URL(string: "https://github.com/login/oauth/authorize?client_id=abc&state=xyz")!)

        let lines = capture.snapshot()
        #expect(lines.count == 2)
        #expect(lines.first == "Open this URL in a browser to authorize:")
        #expect(lines.last == "https://github.com/login/oauth/authorize?client_id=abc&state=xyz")
    }
}

private final class LineCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.lines.append(line)
    }

    func snapshot() -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lines
    }
}
