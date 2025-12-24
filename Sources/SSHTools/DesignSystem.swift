import SwiftUI

struct DesignSystem {
    // MARK: - Colors
    struct Colors {
        static let primary = Color("AccentColor") // Fallback to system accent or define specific
        static let secondary = Color.secondary
        
        // Refined Palette
        static let blue = Color(red: 0.0, green: 0.48, blue: 1.0) // System Blue-ish
        static let purple = Color(red: 0.35, green: 0.34, blue: 0.84)
        static let pink = Color(red: 1.0, green: 0.17, blue: 0.33)
        static let orange = Color(red: 1.0, green: 0.58, blue: 0.0)
        static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
        
        // Backgrounds
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let surfaceSecondary = Color(nsColor: .separatorColor).opacity(0.1) // Compatible flat fill
        
        static let border = Color(nsColor: .separatorColor).opacity(0.5)
        static let text = Color.primary
        static let textSecondary = Color.secondary
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    struct Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
        static let circle: CGFloat = 999
    }
    
    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold, design: .rounded)
        static let title = Font.system(size: 24, weight: .bold, design: .rounded)
        static let headline = Font.system(size: 18, weight: .semibold, design: .default)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)
        static let monospace = Font.system(size: 13, weight: .regular, design: .monospaced)
    }
    
    // MARK: - Layout Constants
    struct Layout {
        static let headerHeight: CGFloat = 32
        static let rowHeight: CGFloat = 28
        static let terminalMinHeight: CGFloat = 100
        static let sftpMinHeight: CGFloat = 30
        static let sftpDefaultHeight: CGFloat = 250
    }
    
    // Backward compatibility helpers (mapped to new structures)
    static let primaryColor = Colors.blue
    static let secondaryColor = Colors.secondary
    static let accentColor = Colors.orange
    static let backgroundColor = Colors.background
    static let surfaceColor = Colors.surface
    static let borderColor = Colors.border
    
    static let spacingSmall = Spacing.small
    static let spacingMedium = Spacing.medium
    static let spacingLarge = Spacing.large
    
    static let cornerRadiusSmall = Radius.small
    static let cornerRadiusMedium = Radius.medium
    static let cornerRadiusLarge = Radius.large
    
    static let fontTitle = Typography.headline
    static let fontHeadline = Typography.headline
    static let fontBody = Typography.body
    static let fontCaption = Typography.caption
}

// MARK: - Reusable Modern Components

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(DesignSystem.Colors.blue)
            Text(title)
                .font(.headline)
        }
        .padding(.leading, 4)
    }
}

struct ModernStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath()
        
        let topLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.minY)
        
        if corners.contains(.topLeft) {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.appendArc(from: topLeft, to: CGPoint(x: rect.minX + radius, y: rect.maxY), radius: radius)
        } else {
            path.move(to: topLeft)
        }
        
        if corners.contains(.topRight) {
            path.line(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
            path.appendArc(from: topRight, to: CGPoint(x: rect.maxX, y: rect.maxY - radius), radius: radius)
        } else {
            path.line(to: topRight)
        }
        
        if corners.contains(.bottomRight) {
            path.line(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
            path.appendArc(from: bottomRight, to: CGPoint(x: rect.maxX - radius, y: rect.minY), radius: radius)
        } else {
            path.line(to: bottomRight)
        }
        
        if corners.contains(.bottomLeft) {
            path.line(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.appendArc(from: bottomLeft, to: CGPoint(x: rect.minX, y: rect.minY + radius), radius: radius)
        } else {
            path.line(to: bottomLeft)
        }
        
        path.close()
        return Path(path.cgPath)
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0 ..< elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            @unknown default:
                break
            }
        }
        return path
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

// MARK: - Components

/// A standardized dashed line for drag operations
struct GhostGuideline: View {
    enum Orientation {
        case horizontal
        case vertical
    }
    
    var orientation: Orientation = .horizontal
    var color: Color = DesignSystem.Colors.blue
    var thickness: CGFloat = 1
    
    var body: some View {
        Group {
            if orientation == .horizontal {
                Rectangle()
                    .fill(color)
                    .frame(height: thickness)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: thickness)
            }
        }
        .overlay(
            Group {
                if orientation == .horizontal {
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: thickness, dash: [4]))
                        .foregroundColor(color)
                } else {
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: thickness, dash: [4]))
                        .foregroundColor(color)
                }
            }
        )
    }
}

/// A standard card container with shadow and background
struct CardView<Content: View>: View {
    let content: Content
    var padding: CGFloat = DesignSystem.Spacing.medium
    
    init(padding: CGFloat = DesignSystem.Spacing.medium, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.Radius.medium)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.5)
            )
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    var icon: String? = nil
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 16)
            }
            configuration
                .textFieldStyle(.plain) // Ensure inner text field is plain to avoid double styling
                .font(DesignSystem.Typography.body)
        }
        .padding(.vertical, 12) // Increased height
        .padding(.horizontal, 16)
        .background(DesignSystem.Colors.surfaceSecondary.opacity(0.5)) // Flat background
        .cornerRadius(DesignSystem.Radius.small)
        // No border, no shadow for flat design
    }
}

struct ModernButtonStyle: ButtonStyle {
    var variant: Variant = .primary
    var size: Size = .regular
    
    enum Variant {
        case primary
        case secondary
        case destructive
        case ghost
    }
    
    enum Size {
        case small
        case regular
        case large
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font(for: size))
            .padding(.vertical, verticalPadding(for: size))
            .padding(.horizontal, horizontalPadding(for: size))
            .background(backgroundColor(for: variant, isPressed: configuration.isPressed))
            .foregroundColor(foregroundColor(for: variant, isPressed: configuration.isPressed))
            .cornerRadius(DesignSystem.Radius.small)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func font(for size: Size) -> Font {
        switch size {
        case .small: return DesignSystem.Typography.caption
        case .regular: return DesignSystem.Typography.body.weight(.medium)
        case .large: return DesignSystem.Typography.headline
        }
    }
    
    private func verticalPadding(for size: Size) -> CGFloat {
        switch size {
        case .small: return 4
        case .regular: return 8
        case .large: return 12
        }
    }
    
    private func horizontalPadding(for size: Size) -> CGFloat {
        switch size {
        case .small: return 8
        case .regular: return 16
        case .large: return 24
        }
    }
    
    private func backgroundColor(for variant: Variant, isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isPressed ? DesignSystem.Colors.blue.opacity(0.8) : DesignSystem.Colors.blue
        case .secondary:
            return isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)
        case .destructive:
            return isPressed ? Color.red.opacity(0.8) : Color.red
        case .ghost:
            return isPressed ? Color.gray.opacity(0.1) : Color.clear
        }
    }
    
    private func foregroundColor(for variant: Variant, isPressed: Bool) -> Color {
        switch variant {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .primary
        case .ghost:
            return isPressed ? .primary : .secondary
        }
    }
}
