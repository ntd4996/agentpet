import AppKit
import AgentPetCore

/// Loads and imports spritesheet pet packs from `~/.agentpet/pets/`.
@MainActor
final class ImagePetStore: ObservableObject {
    static let shared = ImagePetStore()

    @Published private(set) var packs: [ImagePetPack] = []

    private var petsDir: URL {
        URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("pets")
    }

    func pack(id: String) -> ImagePetPack? {
        packs.first { $0.id == id }
    }

    /// Deletes an installed pet's folder from disk. Drops it from the in-memory
    /// list directly instead of a full `reload()`: reload re-slices every other
    /// pack's spritesheet on the main actor (heavy pixel-scan per sheet), which
    /// froze the UI when deleting with many pets installed.
    func delete(_ pack: ImagePetPack) {
        try? FileManager.default.removeItem(at: pack.directory)
        packs.removeAll { $0.id == pack.id }
    }

    func reload() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: petsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            packs = []
            return
        }
        packs = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .compactMap { SpriteSlicer.loadPack(directory: $0) }
            .sorted { $0.displayName < $1.displayName }
    }
}
