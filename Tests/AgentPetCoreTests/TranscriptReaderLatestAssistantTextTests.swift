import XCTest
@testable import AgentPetCore

final class TranscriptReaderLatestAssistantTextTests: XCTestCase {
    private func tempTranscript(_ lines: [String]) throws -> String {
        let path = NSTemporaryDirectory() + "transcript-\(UUID().uuidString).jsonl"
        try Data(lines.joined(separator: "\n").utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    private func assistantLine(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(escaped)"}]}}"#
    }

    private let userLine = #"{"type":"user","message":{"content":[{"type":"text","text":"thanks"}]}}"#

    func testReturnsLatestAssistantTextVerbatim() throws {
        let path = try tempTranscript([
            assistantLine("Working on it now."),
            userLine,
            assistantLine("Which approach do you want — A or B?")
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(TranscriptReader.latestAssistantText(at: path),
                       "Which approach do you want — A or B?")
    }

    func testSkipsTrailingNonAssistantLines() throws {
        let path = try tempTranscript([
            assistantLine("All done — pushed the fix."),
            userLine
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(TranscriptReader.latestAssistantText(at: path),
                       "All done — pushed the fix.")
    }

    func testReturnsNilForUnreadablePath() {
        XCTAssertNil(TranscriptReader.latestAssistantText(at: "/no/such/file-\(UUID().uuidString).jsonl"))
    }

    func testReturnsNilWhenNoAssistantLineExists() throws {
        let path = try tempTranscript([userLine])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertNil(TranscriptReader.latestAssistantText(at: path))
    }
}
