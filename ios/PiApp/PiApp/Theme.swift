import SwiftUI

public enum Theme {
    // MARK: - Primary Colors
    public static let primary = Color("AccentColor", bundle: nil)
    public static let primaryVariant = Color.blue
    public static let onPrimary = Color.white

    // MARK: - Background Colors
    public static let background = Color(uiColor: .systemBackground)
    public static let surface = Color(uiColor: .secondarySystemBackground)
    public static let surfaceVariant = Color(uiColor: .tertiarySystemBackground)

    // MARK: - Chat Bubble Colors
    public static let userBubble = Color.blue
    public static let userBubbleText = Color.white
    public static let assistantBubble = Color(uiColor: .secondarySystemBackground)
    public static let assistantBubbleText = Color(uiColor: .label)

    // MARK: - Tool Colors
    public static let toolBackground = Color(uiColor: .tertiarySystemBackground)
    public static let toolBorder = Color(uiColor: .separator)
    public static let toolHeaderBackground = Color(uiColor: .quaternarySystemFill)

    // MARK: - Diff Colors
    public static let diffAdd = Color.green.opacity(0.2)
    public static let diffAddText = Color.green
    public static let diffRemove = Color.red.opacity(0.2)
    public static let diffRemoveText = Color.red
    public static let diffContext = Color(uiColor: .secondarySystemBackground)

    // MARK: - Status Colors
    public static let error = Color.red
    public static let warning = Color.orange
    public static let success = Color.green
    public static let info = Color.blue

    // MARK: - Text Colors
    public static let textPrimary = Color(uiColor: .label)
    public static let textSecondary = Color(uiColor: .secondaryLabel)
    public static let textTertiary = Color(uiColor: .tertiaryLabel)

    // MARK: - Thinking
    public static let thinkingBackground = Color.purple.opacity(0.1)
    public static let thinkingBorder = Color.purple.opacity(0.3)
    public static let thinkingText = Color.purple

    // MARK: - Spacing
    public static let paddingSmall: CGFloat = 4
    public static let paddingMedium: CGFloat = 8
    public static let paddingLarge: CGFloat = 16
    public static let paddingXLarge: CGFloat = 24

    // MARK: - Corner Radius
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadius: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 16

    // MARK: - Font
    public static let codeFont = Font.system(.body, design: .monospaced)
    public static let codeFontSmall = Font.system(.caption, design: .monospaced)
}
