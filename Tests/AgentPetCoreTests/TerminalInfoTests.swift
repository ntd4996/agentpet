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

    /// `procInfo` must agree with `ps`, which it replaced for the ancestor walk.
    func testProcInfoMatchesPS() throws {
        let pid = getpid()
        let info = try XCTUnwrap(TerminalInfo.procInfo(pid: pid))
        XCTAssertEqual(info.ppid, getppid())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let ps = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(info.tty, ps == "??" ? nil : "/dev/\(ps)")
    }

    func testProcInfoNilForMissingProcess() {
        XCTAssertNil(TerminalInfo.procInfo(pid: 99_999_999))
    }
}
