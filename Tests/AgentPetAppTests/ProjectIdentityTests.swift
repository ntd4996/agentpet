import XCTest
import AgentPetCore
@testable import agentpet

/// Custom names are looked up by `ProjectNames.id`, usage rows are stored under
/// `ProjectUsageStore.projectIdentity`. They must always agree, or a name set from
/// the usage-derived Settings list would silently stop matching its project.
@MainActor
final class ProjectIdentityTests: XCTestCase {
    func testUsageIdentityUsesTheSameIdAsProjectNames() {
        let paths = ["", "/", "/Users/me/Projects", "/Users/me/Dự án/ứng dụng", "/tmp/日本語/プロジェクト",
                     "/tmp/emoji 🐉/x", String(repeating: "/a", count: 200)]
        for p in paths {
            XCTAssertEqual(ProjectUsageStore.projectIdentity(p).id, ProjectNames.id(for: p), p)
        }
    }

    func testUsageIdentityNameIsTheFolderCappedAtSixty() {
        XCTAssertEqual(ProjectUsageStore.projectIdentity("/Users/me/helm-claw").name, "helm-claw")
        XCTAssertEqual(ProjectUsageStore.projectIdentity("/").name, "/")
        let long = "/x/" + String(repeating: "n", count: 100)
        XCTAssertEqual(ProjectUsageStore.projectIdentity(long).name.count, 60)
    }
}
