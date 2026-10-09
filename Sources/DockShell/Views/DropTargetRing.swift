import SwiftUI

extension View {
    /// A ring just outside the view while `shown`, saying a drag over it would land on it:
    /// the Trash's highlight, and a widget tile's when it takes the drag.
    func dropTargetRing(shown: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if shown {
                RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                    .strokeBorder(.primary.opacity(0.7), lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}
