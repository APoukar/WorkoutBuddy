import SwiftUI

/// Pins the main action(s) of a screen at the bottom, in thumb reach. From iOS 26 the system bar and
/// its scroll-edge effect are used; before that, the content sits over a `.bar` background so
/// scrolling rows don't show through. The builder's views are stacked with 8 pt between them.
private struct CoveredByLayerKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether another layer (the review, the paused overlay) covers this screen. A covered screen is
    /// hidden from VoiceOver completely, including its header and bottom bar.
    var isCoveredByLayer: Bool {
        get { self[CoveredByLayerKey.self] }
        set { self[CoveredByLayerKey.self] = newValue }
    }
}

private struct HiddenWhenCovered: ViewModifier {
    @Environment(\.isCoveredByLayer) private var covered

    func body(content: Content) -> some View {
        content.accessibilityHidden(covered)
    }
}

extension View {
    /// Hides the view from VoiceOver while `isCoveredByLayer` is set.
    func accessibilityHiddenWhenCovered() -> some View {
        modifier(HiddenWhenCovered())
    }
}

private struct BottomActionBar<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) { stack }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { stack.background(.bar) }
        }
    }

    private var stack: some View {
        VStack(spacing: 8) { bar }
            .padding()
            .frame(maxWidth: .infinity)
            .accessibilityHiddenWhenCovered()
    }
}

extension View {
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(BottomActionBar(bar: bar()))
    }
}
