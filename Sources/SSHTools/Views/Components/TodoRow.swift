import SwiftUI

struct TodoRow: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onUpdate: (TodoItem) -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(item.isCompleted ? DesignSystem.Colors.green : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DesignSystem.Typography.body)
                    .strikethrough(item.isCompleted)
                    .foregroundColor(item.isCompleted ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.text)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .background(Color.clear)
    }
}
