import SwiftUI

/// The pet sprite alone (imported pack, reacting to mood). Shows a paw
/// placeholder if no pet is selected yet.
struct PetView: View {
    var size: CGFloat = 120
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var bindings = PetBindingsStore.shared
    @ObservedObject private var window = PetWindowController.shared

    var body: some View {
        content
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if let id = pet.selectedPetID, let pack = imagePets.pack(id: id) {
            let clipIndex: Int = {
                if window.isMoving {
                    return min(window.moveClipIndex, pack.clipCount - 1)
                }
                if pet.mood == .idle {
                    return min(window.idleClipIndex, pack.clipCount - 1)
                }
                return bindings.clipIndex(packId: pack.id, clipCount: pack.clipCount, mood: pet.mood)
            }()
            let renderDirection: CGFloat = {
                if window.isMoving {
                    return window.moveScaleX
                }
                return window.direction
            }()
            ImageSpriteView(frames: pack.clip(clipIndex), mood: pet.mood, size: size,
                            isMoving: window.isMoving, direction: renderDirection,
                            isResting: window.isResting)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
        }
    }
}

/// The full floating window content: a chat bubble above the pet.
struct FloatingPetView: View {
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        VStack(spacing: 2) {
            if pet.showChat && !pet.chatLine.isEmpty && pet.selectedPetID != nil {
                ChatBubble(text: pet.chatLine)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            PetView(size: pet.petPoint)
        }
        .frame(width: pet.windowSize.width, height: pet.windowSize.height, alignment: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pet.chatLine)
        .animation(.easeInOut, value: pet.showChat)
    }
}

/// A speech bubble with a little downward tail.
private struct ChatBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Triangle()
                .fill(.white)
                .frame(width: 12, height: 7)
        }
        .fixedSize()
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
