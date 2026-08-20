import XCTest

/// Walks every screen the app has and attaches a screenshot of each.
///
/// This is a smoke test, not a pixel test — it asserts that each screen reaches
/// a state with real content in it, and leaves the screenshots behind so the
/// visual result can be reviewed without rebuilding by hand. Nothing here
/// touches the network, because there is nothing to touch.
final class WalkthroughTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testWalksEveryScreen() {
        // The app opens on the search canvas, not on Today.
        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The search canvas never appeared"
        )
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        capture("01-launch-search-canvas")

        openToday()
        openBrowseAndIsnad()
        openLibrary()
        openSearch()
    }

    /// Today is a tab away from the launch screen now, and on iOS 26 selecting
    /// the search tab collapses the rest of the tab bar — so this is also the
    /// check that the other tabs are still reachable at all.
    private func openToday() {
        tap(app.tabButton("Today"), "the Today tab", in: app)
        XCTAssertTrue(
            app.staticTexts["Hadith of the Day"].waitForExistence(timeout: 20),
            "Today never loaded — the corpus probably failed to open"
        )
        // The daily hadith comes from the database, so its presence proves the
        // store opened and the day-of-year lookup resolved.
        XCTAssertTrue(app.staticTexts["Read in full"].waitForExistence(timeout: 20))
        capture("02-today")
        openDailyHadith()
    }

    private func openDailyHadith() {
        app.staticTexts["Read in full"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        capture("03-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openBrowseAndIsnad() {
        tap(app.tabButton("Browse"), "the Browse tab", in: app)
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari"].waitForExistence(timeout: 10))
        capture("04-browse")

        app.staticTexts["Sahih al-Bukhari"].tap()
        // "Revelation" is Bukhari's first chapter. Asserting on the name rather
        // than an index also proves the chapters table survived the pipeline.
        let firstChapter = app.staticTexts["Revelation"]
        XCTAssertTrue(firstChapter.waitForExistence(timeout: 10))
        capture("05-collection")

        firstChapter.tap()
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari 1"].waitForExistence(timeout: 10))
        capture("06-chapter")

        // Bukhari 1 has a parsed isnad, so this reliably reaches the chain view
        // — the daily hadith does not always have one.
        app.staticTexts["Sahih al-Bukhari 1"].tap()
        // Matched by identifier, not by the label text — a copy edit should
        // not break a navigation test.
        let chainLink = app.descendants(matching: .any)["isnadLink"]
        XCTAssertTrue(chainLink.waitForExistence(timeout: 10), "Bukhari 1 should expose its isnad")
        capture("07-detail-bukhari-1")

        chainLink.tap()
        XCTAssertTrue(app.navigationBars["Chain of Narrators"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Collector"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Source"].exists)
        capture("08-isnad")

        // Pop all the way back to the Browse tab root — isnad → detail →
        // chapter → collection → root — rather than the two taps that used to
        // stop at the chapter view. `openLibrary()` below needs a tab root:
        // the bookmark toolbar item lives on `TodayView`, `BrowseView`, and
        // `SearchView`, not on `ChapterView`.
        for _ in 0..<4 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Nothing else in the suite ever presents this sheet — `libraryButton`
    /// otherwise only appears in `LibraryUITests`, which doesn't screenshot
    /// it — so this is the coverage that would have caught the `List`
    /// migration drawing a system disclosure chevron on every row.
    private func openLibrary() {
        tap(app.buttons["libraryButton"], "the library button", in: app)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))

        // Saved starts empty — nothing in this walkthrough stars a hadith —
        // so the default segment should show its empty state.
        XCTAssertTrue(
            app.staticTexts["Nothing saved yet"].waitForExistence(timeout: 10),
            "Saved should show its empty state — nothing in this walkthrough stars a hadith"
        )
        capture("09-library-saved")

        // Recent isn't empty by this point — Today and Bukhari 1 were both
        // opened above, and opening a hadith records it — so this segment
        // should list real rows, not its empty state.
        tap(app.buttons["Recent"], "the Recent segment", in: app)
        XCTAssertTrue(
            app.staticTexts["Sahih al-Bukhari 1"].waitForExistence(timeout: 10),
            "Recent should list Bukhari 1, opened earlier in this walkthrough"
        )
        capture("10-library-recent")

        tap(app.buttons["Done"], "Done", in: app)
    }

    private func openSearch() {
        tap(app.searchTabButton, "the Search tab", in: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search field never appeared")
        capture("11-search-empty")

        field.tap()
        field.typeText("kindness to neighbours")

        // The debounce is 300ms and a cold Core ML load can take a couple of
        // seconds, so this waits on content rather than a fixed sleep.
        let results = app.scrollViews.firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 30))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "%")).firstMatch
                .waitForExistence(timeout: 30),
            "No scored results appeared for a query that should match"
        )
        capture("12-search-results")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
