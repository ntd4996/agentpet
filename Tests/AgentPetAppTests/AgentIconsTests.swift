import XCTest
@testable import agentpet

@MainActor
final class AgentIconsTests: XCTestCase {
    /// Every kind offered in the brand-logo picker must actually decode to an
    /// image; a kind listed there without artwork would show a blank cell.
    func testEveryBrandKindHasAnImage() {
        for kind in AgentIcons.brandKinds {
            XCTAssertNotNil(AgentIcons.image(for: kind), "\(kind.rawValue) has no brand image")
        }
    }

    func testJcodeLogoDecodesAtEmbeddedSize() throws {
        let img = try XCTUnwrap(AgentIcons.image(for: .jcode))
        let rep = try XCTUnwrap(img.representations.first)
        XCTAssertEqual(rep.pixelsWide, 64)
        XCTAssertEqual(rep.pixelsHigh, 64)
    }
}
