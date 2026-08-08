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
        capture("01-today")
        XCTAssertTrue(
            app.staticTexts["Hadith of the Day"].waitForExistence(timeout: 20),
            "Today never loaded — the corpus probably failed to open"
        )
        // The daily hadith comes from the database, so its presence proves the
        // store opened and the day-of-year lookup resolved.
        XCTAssertTrue(app.staticTexts["Read in full"].waitForExistence(timeout: 20))
        capture("02-today-loaded")

        openDailyHadith()
        openBrowseAndIsnad()
        openSearch()
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

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openSearch() {
        tap(app.searchTabButton, "the Search tab", in: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search field never appeared")
        capture("09-search-empty")

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
        capture("10-search-results")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
