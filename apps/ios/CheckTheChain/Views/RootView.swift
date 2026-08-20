import SwiftUI
import HadithKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.state {
        case .loading:
            LoadingView()
        case .failed(let message):
            FailureView(message: message)
        case .ready(let corpus):
            MainTabs(corpus: corpus)
        }
    }
}

private struct MainTabs: View {
    let corpus: Corpus

    private enum Section: Hashable { case today, browse, search }

    /// The app opens on search.
    ///
    /// Verifying a hadith someone sent you is the thing this app is for, and
    /// with `Tab(role: .search)` the tab bar itself becomes the search field —
    /// so launching here gives an almost empty screen with one obvious control
    /// at the bottom, rather than a card the reader didn't ask for.
    @State private var section: Section = .search

    /// Published so UI tests can assert which appearance actually resolved.
    /// XCTest has no API to set the interface style, and a launch-argument
    /// override would be a test hook in shipping code — so the appearance is set
    /// on the simulator (`scripts/uitest.sh`) and read back here.
    @Environment(\.colorScheme) private var colorScheme

    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var savedState = app.savedState

        TabView(selection: $section) {
            Tab("Today", systemImage: "sun.horizon", value: Section.today) {
                TodayView(corpus: corpus)
            }
            Tab("Browse", systemImage: "books.vertical", value: Section.browse) {
                BrowseView(corpus: corpus)
            }
            // The search role turns this into the bottom search field that
            // sits beside the tab bar rather than a fourth tab icon.
            Tab(value: Section.search, role: .search) {
                SearchView(corpus: corpus) { section = .browse }
            }
        }
        // The tab bar shrinks out of the way while reading a long hadith and
        // comes back on scroll up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .accessibilityIdentifier(colorScheme == .dark ? "appearance-dark" : "appearance-light")
        // The one place `SavedState.errorMessage` is surfaced. Mounted once,
        // here, rather than once per screen: every screen under this tab
        // view shares the same `SavedState`, and attaching this same alert
        // at every context-menu row and every detail-page star would mean
        // several `.alert` instances simultaneously bound to the same
        // property — undefined when more than one is presented at once.
        // One alert, at the root of the content that's always mounted while
        // any of those surfaces can fire, is the version that can't collide
        // with itself.
        .saveErrorAlert($savedState.errorMessage)
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .tint(Palette.inkMuted)
        }
    }
}

private struct FailureView: View {
    let message: String

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            ContentUnavailableView {
                Label("Couldn't open the collection", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
    }
}
