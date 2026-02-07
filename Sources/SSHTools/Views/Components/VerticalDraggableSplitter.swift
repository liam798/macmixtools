import SwiftUI
import AppKit

struct VerticalDraggableSplitter: View {
    @Binding var isDragging: Bool
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(width: 2)
            
            if isDragging {
                Rectangle()
                    .fill(DesignSystem.Colors.blue)
                    .frame(width: 3)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DesignSystem.Colors.textSecondary.opacity(0.25))
                    .frame(width: 3, height: 36)
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
