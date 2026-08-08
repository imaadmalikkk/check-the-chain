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

    /// Published so UI tests can assert which appearance actually resolved.
    /// XCTest has no API to set the interface style, and a launch-argument
    /// override would be a test hook in shipping code — so the appearance is set
    /// on the simulator (`scripts/uitest.sh`) and read back here.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon") {
                TodayView(corpus: corpus)
            }
            Tab("Browse", systemImage: "books.vertical") {
                BrowseView(corpus: corpus)
            }
            // The search role turns this into the bottom search field that
            // sits beside the tab bar rather than a fourth tab icon.
            Tab(role: .search) {
                SearchView(corpus: corpus)
            }
        }
        // The tab bar shrinks out of the way while reading a long hadith and
        // comes back on scroll up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .accessibilityIdentifier(colorScheme == .dark ? "appearance-dark" : "appearance-light")
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
