import SwiftUI
import AppKit

struct VerticalDraggableSplitter: View {
    @Binding var isDragging: Bool
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.8))
                .frame(width: 1)
            
            if isDragging {
                Rectangle()
                    .fill(DesignSystem.Colors.blue)
                    .frame(width: 2)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DesignSystem.Colors.textSecondary.opacity(0.25))
                    .frame(width: 2, height: 36)
            }
        }
        .frame(width: DesignSystem.Layout.sidebarSplitterWidth)
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .zIndex(100)
    }
}
