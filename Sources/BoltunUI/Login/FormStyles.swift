import SwiftUI

struct FormFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct InlineError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inline-error")
        }
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Theme.brandGradient)
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.04)
    }
}
