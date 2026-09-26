import SwiftUI

/// Returns each tab to the top of its content when the tab bar is used.
///
/// `TabView` preserves every tab's scroll offset, so coming back to Overview
/// after scrolling down leaves you halfway through the screen, looking at a
/// category bar with no idea what month it belongs to. The number at the top is
/// the one that matters on every tab in this app — the leak total, the queue
/// count, the range picker — and it should be the thing you see.
///
/// Deliberately **not** done by rebuilding the view with `.id()`, which would
/// also reset the Analysis range picker and any other in-tab state. Scrolling
/// and forgetting are different things; this only scrolls.
///
/// Two moves trigger it, matching what iOS does elsewhere:
/// - switching to a different tab
/// - tapping the tab you are already on
enum ScrollToTop {

    /// Identifies the first element inside a tab's scroll container.
    static let anchor = "cashleak.scroll-to-top"
}

private struct ScrollToTopSignalKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {

    /// Incremented by `RootTabView` on every tab bar interaction.
    ///
    /// A counter rather than the selected tab, because tapping the current tab
    /// has to register too — and that isn't a change of value.
    var scrollToTopSignal: Int {
        get { self[ScrollToTopSignalKey.self] }
        set { self[ScrollToTopSignalKey.self] = newValue }
    }
}

extension View {

    /// Wraps a tab's root scroll container so it scrolls back to the top.
    ///
    /// Applied to the `ScrollView` or `List` itself, not to the enclosing
    /// `NavigationStack`: the reader has to sit close to the container it
    /// drives, and pushed detail screens already open at the top on their own.
    func scrollsToTopOnTabChange() -> some View {
        modifier(ScrollToTopOnTabChange())
    }

    /// Marks the first element inside the container as the top.
    ///
    /// `scrollTo` needs something to aim at, and every one of these tabs starts
    /// with a view that is already stable and stateless — a card, a section, a
    /// picker. Nothing is inserted just to be scrolled to.
    func scrollToTopAnchor() -> some View {
        id(ScrollToTop.anchor)
    }
}

private struct ScrollToTopOnTabChange: ViewModifier {

    @Environment(\.scrollToTopSignal) private var signal

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: signal) { _, _ in
                // Unanimated. The tab is changing underneath this, so an
                // animated scroll plays against the tab transition and reads as
                // the content sliding twice.
                proxy.scrollTo(ScrollToTop.anchor, anchor: .top)
            }
        }
    }
}
