import AppKit
import DockCore
import DockWidgetKit
import SwiftUI

extension ShortcutTint {
    /// The system color of the same name, as the Shortcuts app's icons use.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }

    var displayName: String { rawValue.capitalized }
}

/// Resolves a stored symbol name to one this Mac can draw.
enum ShortcutSymbolResolver {
    /// `name` when it's an SF Symbol here, else the default. Empty names are the default too.
    static func symbol(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil else {
            return ShortcutSymbols.default
        }
        return trimmed
    }
}

/// A shortcut's icon as the Shortcuts app draws it: a white symbol on a rounded square of
/// the shortcut's color, with the run's state as a small badge or a spinner.
struct ShortcutIconView: View {
    let symbol: String
    let tint: ShortcutTint
    let size: Double
    var state: ShortcutRunState?
    /// Whether a success or failure badge is still showing; the tile hides it after a moment.
    var showsOutcome = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [tint.color.opacity(0.95), tint.color.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom))
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(state?.isRunning == true ? 0.35 : 1)
            if state?.isRunning == true {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .scaleEffect(size / 40)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if showsOutcome, let badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: size * 0.3, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, badge.color)
                    .background(Circle().fill(.white).padding(-1))
                    .offset(x: size * 0.1, y: size * 0.1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animationRespectingReduceMotion(.snappy(duration: 0.25), value: showsOutcome)
        .animationRespectingReduceMotion(.snappy(duration: 0.25), value: state)
        .accessibilityHidden(true)
    }

    private var badge: (symbol: String, color: Color)? {
        switch state {
        case .succeeded: return (symbol: "checkmark.circle.fill", color: .green)
        case .failed: return (symbol: "exclamationmark.circle.fill", color: .red)
        case .running, nil: return nil
        }
    }
}
