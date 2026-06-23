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

    /// Full synchronous reload. Used after importing a pet, where slicing every
    /// pack up front is acceptable; launch uses `loadFast` to stay responsive.
    func reload() {
        packs = Self.directories(in: petsDir)
            .compactMap { SpriteSlicer.loadPack(directory: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Launch path: slice only the prioritised pack synchronously so the pet and
    /// menu bar can appear immediately, then slice the remaining packs on later
    /// run-loop ticks (yielding between each) so a large library never blocks the
    /// app from showing up.
    func loadFast(priorityID: String?) {
        let dirs = Self.directories(in: petsDir)
        let priorityDir = priorityID
            .flatMap { pid in dirs.first { SpriteSlicer.manifestID(directory: $0) == pid } }
            ?? dirs.first
        if let pd = priorityDir, let pack = SpriteSlicer.loadPack(directory: pd) {
            packs = [pack]
        }
        let rest = dirs.filter { $0 != priorityDir }
        guard !rest.isEmpty else { return }
        Task { @MainActor in
            // Slice the rest into a local accumulator and publish ONCE at the end.
            // Re-assigning `packs` per pet made PetView (which observes the store)
            // re-render on every pet, stuttering the sprite animation at launch.
            var acc = packs
            for dir in rest {
                await Task.yield()   // let the menu bar + pet paint first
                guard let pack = SpriteSlicer.loadPack(directory: dir) else { continue }
                acc.append(pack)
            }
            packs = acc.sorted { $0.displayName < $1.displayName }
        }
    }

    private static func directories(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}
