import SwiftUI
import AppKit

struct DraggableSplitter: View {
    @Binding var isDragging: Bool
    @Binding var offset: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    
    var body: some View {
        let hitHeight: CGFloat = DesignSystem.Layout.terminalSplitterHeight
        ZStack {
            // Base line
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 2)
            
            // Minimal handle
            RoundedRectangle(cornerRadius: 1)
                .fill(DesignSystem.Colors.textSecondary.opacity(0.25))
                .frame(width: 44, height: 3)
            
            if isDragging {
                Rectangle()
                    .fill(DesignSystem.Colors.blue)
                    .frame(height: 3)
                    .offset(y: offset)
                    .allowsHitTesting(false)
            }
            
            // Hit area for gesture (Topmost)
            Color.clear
                .frame(height: hitHeight)
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
                        NSCursor.resizeUpDown.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        }
        .zIndex(1)
    }
}
