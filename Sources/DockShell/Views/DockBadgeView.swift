import AppKit
import SwiftUI

extension View {
    /// Draws `label` as an app badge at the view's top-right corner. Apply it to the icon
    /// before anything that moves the icon after layout (the launch bounce), so the badge
    /// moves with it.
    func dockBadge(_ label: String?) -> some View {
        overlay {
            if let label {
                DockBadgeView(label: label)
            }
        }
    }
}

/// An app's badge as Apple's Dock draws it: white text on a red pill over the icon's top-right
/// corner. It's sized from the icon as laid out, so it grows with magnification and is drawn
/// sharp at every size. Labels too long for the icon are cut short.
struct DockBadgeView: View {
    let label: String

    /// Height of the badge as a share of the icon's side.
    static let heightRatio: CGFloat = 0.36
    /// How far the badge reaches past the icon's top and right edges, as a share of its side.
    static let overhangRatio: CGFloat = 0.04

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let height = side * Self.heightRatio
            Text(label)
                .font(.system(size: height * 0.64, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, height * 0.3)
                .frame(minWidth: height, minHeight: height, maxHeight: height)
                .background(Capsule().fill(Color(nsColor: .systemRed)))
                .shadow(color: .black.opacity(0.25), radius: height * 0.06, y: height * 0.03)
                .frame(maxWidth: side, alignment: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: side * Self.overhangRatio, y: -side * Self.overhangRatio)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
