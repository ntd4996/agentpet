import Foundation
import AgentPetCore

public enum ClipCategory: String, Codable, CaseIterable {
    case inplace = "inplace"
    case jump = "jump"
    case runLeft = "runLeft"
    case runRight = "runRight"
    case runLeftAutoFlip = "runLeftAutoFlip"
    case runRightAutoFlip = "runRightAutoFlip"

    public var displayName: String {
        switch self {
        case .inplace: return "Tại chỗ"
        case .jump: return "Nhảy"
        case .runLeft: return "Chạy trái"
        case .runRight: return "Chạy phải"
        case .runLeftAutoFlip: return "Trái tự lật"
        case .runRightAutoFlip: return "Phải tự lật"
        }
    }
}

/// Maps each pet state to a clip index of an imported sprite pet.
struct PetBindings: Equatable {
    var byMood: [String: Int]

    func clipIndex(for mood: PetMood) -> Int {
        byMood[mood.rawValue] ?? 0
    }

    /// Spreads the first clips across states, clamped to what the pack has.
    static func defaults(clipCount: Int) -> PetBindings {
        let order: [PetMood] = [.idle, .working, .waiting, .done, .celebrate]
        var map: [String: Int] = [:]
        for (i, mood) in order.enumerated() {
            map[mood.rawValue] = clipCount > 0 ? min(i, clipCount - 1) : 0
        }
        return PetBindings(byMood: map)
    }
}

/// Persists per-pet state→clip bindings and publishes changes to the UI.
@MainActor
final class PetBindingsStore: ObservableObject {
    static let shared = PetBindingsStore()

    @Published private var cache: [String: PetBindings] = [:]
    @Published private var categoriesCache: [String: [Int: String]] = [:]

    func bindings(packId: String, clipCount: Int) -> PetBindings {
        if let cached = cache[packId] { return cached }
        let loaded = load(packId) ?? PetBindings.defaults(clipCount: clipCount)
        cache[packId] = loaded
        return loaded
    }

    func clipIndex(packId: String, clipCount: Int, mood: PetMood) -> Int {
        min(bindings(packId: packId, clipCount: clipCount).clipIndex(for: mood), max(clipCount - 1, 0))
    }

    func setClip(_ clip: Int, mood: PetMood, packId: String, clipCount: Int) {
        var current = bindings(packId: packId, clipCount: clipCount)
        current.byMood[mood.rawValue] = clip
        cache[packId] = current
        save(packId, current)
    }

    func category(packId: String, clipIndex: Int) -> ClipCategory {
        if let cached = categoriesCache[packId] {
            if let str = cached[clipIndex], let cat = ClipCategory(rawValue: str) {
                return cat
            }
        } else {
            let loaded = loadCategories(packId)
            categoriesCache[packId] = loaded
            if let str = loaded[clipIndex], let cat = ClipCategory(rawValue: str) {
                return cat
            }
        }
        // Default rules:
        // - Clip index 1 is default movement (right auto-flip).
        // - Clip index 2 is default jump.
        // - All others are in-place.
        if clipIndex == 1 {
            return .runRightAutoFlip
        } else if clipIndex == 2 {
            return .jump
        } else {
            return .inplace
        }
    }

    func setCategory(_ category: ClipCategory, for clipIndex: Int, packId: String) {
        var current = categoriesCache[packId] ?? loadCategories(packId)
        current[clipIndex] = category.rawValue
        categoriesCache[packId] = current
        saveCategories(packId, current)
    }

    private func key(_ packId: String) -> String { "agentpet.bindings.\(packId)" }
    private func categoriesKey(_ packId: String) -> String { "agentpet.categories.\(packId)" }

    private func load(_ packId: String) -> PetBindings? {
        guard let data = UserDefaults.standard.data(forKey: key(packId)),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return nil }
        return PetBindings(byMood: map)
    }

    private func save(_ packId: String, _ bindings: PetBindings) {
        if let data = try? JSONEncoder().encode(bindings.byMood) {
            UserDefaults.standard.set(data, forKey: key(packId))
        }
    }

    private func loadCategories(_ packId: String) -> [Int: String] {
        guard let data = UserDefaults.standard.data(forKey: categoriesKey(packId)),
              let map = try? JSONDecoder().decode([Int: String].self, from: data) else { return [:] }
        return map
    }

    private func saveCategories(_ packId: String, _ map: [Int: String]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: categoriesKey(packId))
        }
    }
}
