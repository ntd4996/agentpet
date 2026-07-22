import XCTest
@testable import AgentPetCore

final class TerminalInfoTests: XCTestCase {
    func testCaptureReadsTermProgramFromEnv() {
        let (program, _) = TerminalInfo.capture(env: ["TERM_PROGRAM": "WarpTerminal"])
        XCTAssertEqual(program, "WarpTerminal")
    }

    func testCaptureTreatsMissingTermProgramAsNil() {
        let (program, _) = TerminalInfo.capture(env: [:])
        XCTAssertNil(program)
    }

    func testCaptureTreatsEmptyTermProgramAsNil() {
        let (program, _) = TerminalInfo.capture(env: ["TERM_PROGRAM": ""])
        XCTAssertNil(program, "an empty TERM_PROGRAM should disable the affordance, not enable it")
    }
}
