import SwiftUI
import AgentPetCore

/// Body motion for a given mood at time `t`, shared by all pet renderers.
struct PetMotion {
    var offsetY: CGFloat
    var rotation: Double
    var scaleX: CGFloat
    var scaleY: CGFloat

    static func resolve(_ mood: PetMood, _ t: Double, isMoving: Bool = false, direction: CGFloat = 1) -> PetMotion {
        if isMoving {
            let step = sin(t * 14)
            return PetMotion(offsetY: -abs(step) * 7,
                             rotation: sin(t * 14) * 3,
                             scaleX: direction,
                             scaleY: 1 + 0.03 * (1 - abs(step)))
        }
        switch mood {
        case .working:
            return PetMotion(offsetY: -abs(sin(t * 6)) * 5, rotation: sin(t * 12) * 2, scaleX: 1, scaleY: 1)
        case .waiting:
            return PetMotion(offsetY: sin(t * 2.6) * 1.5, rotation: sin(t * 2.6) * 7, scaleX: 1, scaleY: 1)
        case .celebrate:
            let hop = abs(sin(t * 4))
            return PetMotion(offsetY: -hop * 11, rotation: sin(t * 8) * 5,
                             scaleX: 1 + 0.05 * (1 - hop), scaleY: 1 - 0.05 * (1 - hop))
        case .done:
            return PetMotion(offsetY: sin(t * 2) * 2.5, rotation: 0, scaleX: 1, scaleY: 1)
        case .idle:
            let b = sin(t * 1.7)
            return PetMotion(offsetY: b * 2, rotation: 0, scaleX: 1 + 0.02 * b, scaleY: 1 - 0.02 * b)
        }
    }
}

/// Mood overlays shared by all pet renderers: sparkles while celebrating and a
/// "?" bubble while waiting.
struct MoodAccessories: View {
    let mood: PetMood
    let t: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            if mood == .celebrate {
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) / 4 * .pi * 2
                    let twinkle = 0.35 + 0.65 * abs(sin(t * 4 + Double(i)))
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                        .opacity(twinkle)
                        .offset(x: cos(angle) * size * 0.34, y: -abs(sin(angle)) * size * 0.34 - size * 0.06)
                }
            }
        }
    }
}
