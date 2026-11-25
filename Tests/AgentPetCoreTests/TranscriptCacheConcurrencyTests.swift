import XCTest
@testable import AgentPetCore

final class TranscriptCacheConcurrencyTests: XCTestCase {
    func testConcurrentTitleRecapAndCacheClearing() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("transcript-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            TranscriptReader.clearCache()
            try? FileManager.default.removeItem(at: directory)
        }
        let paths = try (0..<32).map { index in
            let url = directory.appendingPathComponent("\(index).jsonl")
            let transcript = """
            {"type":"summary","summary":"summary-\(index)"}
            {"type":"assistant","message":{"content":"Recap: recap-\(index)"}}

            """
            try Data(transcript.utf8).write(to: url)
            return url.path
        }
        TranscriptReader.clearCache()
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            for iteration in 0..<100 {
                XCTAssertEqual(TranscriptReader.title(at: paths[index]), "summary-\(index)")
                XCTAssertEqual(TranscriptReader.latestAssistantRecap(at: paths[index]), "recap-\(index)")
                if iteration % 10 == 0 { TranscriptReader.clearCache() }
            }
        }
    }
}
