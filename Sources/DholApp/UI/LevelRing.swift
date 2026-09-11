import SwiftUI

/// A ring whose centre swells with the microphone level, so you can see that
/// Dhol is actually hearing you rather than only claiming to listen.
struct LevelRing: View {
    let level: Float
    var color: Color = .red

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .stroke(color.opacity(0.28), lineWidth: side * 0.09)
                Circle()
                    .fill(color)
                    .frame(width: side * (0.3 + CGFloat(min(max(level, 0), 1)) * 0.5))
            }
            .frame(width: side, height: side)
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
