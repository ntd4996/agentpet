import XCTest
@testable import AgentPetCore

final class TerminalInfoTests: XCTestCase {
    func testCaptureReadsTermProgramFromEnv() {
        let c = TerminalInfo.capture(env: ["TERM_PROGRAM": "WarpTerminal"])
        XCTAssertEqual(c.program, "WarpTerminal")
    }

    func testCaptureTreatsMissingTermProgramAsNil() {
        XCTAssertNil(TerminalInfo.capture(env: [:]).program)
    }

    func testCaptureTreatsEmptyTermProgramAsNil() {
        XCTAssertNil(TerminalInfo.capture(env: ["TERM_PROGRAM": ""]).program,
                     "an empty TERM_PROGRAM should disable the affordance, not enable it")
    }

    func testCaptureReadsWarpFocusURL() {
        let c = TerminalInfo.capture(env: [
            "TERM_PROGRAM": "WarpTerminal",
            "WARP_FOCUS_URL": "warp://session/abc123",
        ])
        XCTAssertEqual(c.focusURL, "warp://session/abc123")
    }

    func testCaptureFocusURLNilWhenAbsent() {
        XCTAssertNil(TerminalInfo.capture(env: ["TERM_PROGRAM": "Apple_Terminal"]).focusURL)
    }
}
