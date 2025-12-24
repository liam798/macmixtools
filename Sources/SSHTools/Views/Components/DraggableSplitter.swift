import SwiftUI

struct DraggableSplitter: View {
    @Binding var isDragging: Bool
    @Binding var offset: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    
    var body: some View {
        ZStack {
            // Static Divider background
            Divider()
            
            // Moving Dashed Guideline (Visual only)
            GhostGuideline(orientation: .horizontal, color: DesignSystem.Colors.blue)
                .offset(y: offset)
                .opacity(isDragging ? 1 : 0)
                .allowsHitTesting(false)
            
            // Hit area for gesture (Topmost)
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            onDragChanged(value.translation.height)
                        }
                        .onEnded { value in
                            onDragEnded(value.translation.height)
                        }
                )
                .onHover { inside in
                    if inside {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .zIndex(1)
    }
}
