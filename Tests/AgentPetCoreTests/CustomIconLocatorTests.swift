import XCTest
@testable import AgentPetCore

/// `~/.agentpet/icons/<name>.<ext>` gives a custom agent a real icon instead
/// of the lettered badge. These lock the lookup rules: case-insensitive name,
/// supported extensions only, png preferred, nil when the dir is missing.
final class CustomIconLocatorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpet-icons-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func touch(_ name: String) throws {
        try Data([0x89]).write(to: dir.appendingPathComponent(name))
    }

    func testFindsIconByNameCaseInsensitively() throws {
        try touch("Forge.png")
        XCTAssertEqual(CustomIconLocator.iconURL(forAgentName: "forge", in: dir)?.lastPathComponent, "Forge.png")
        XCTAssertEqual(CustomIconLocator.iconURL(forAgentName: "FORGE", in: dir)?.lastPathComponent, "Forge.png")
    }

    func testPrefersPNGOverSVGWhenBothExist() throws {
        try touch("forge.svg")
        try touch("forge.png")
        XCTAssertEqual(CustomIconLocator.iconURL(forAgentName: "forge", in: dir)?.pathExtension, "png")
    }

    func testIgnoresUnsupportedExtensionsAndOtherNames() throws {
        try touch("forge.txt")
        try touch("hermes.png")
        XCTAssertNil(CustomIconLocator.iconURL(forAgentName: "forge", in: dir))
    }

    func testMissingDirectoryOrEmptyNameIsNil() {
        let missing = dir.appendingPathComponent("nope", isDirectory: true)
        XCTAssertNil(CustomIconLocator.iconURL(forAgentName: "forge", in: missing))
        XCTAssertNil(CustomIconLocator.iconURL(forAgentName: "  ", in: dir))
    }
}
