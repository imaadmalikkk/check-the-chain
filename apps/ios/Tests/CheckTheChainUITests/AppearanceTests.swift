import XCTest

/// Exercises the app under conditions the default simulator never shows:
/// dark mode, the largest accessibility text size, and a hadith with a
/// pathologically long attribution.
///
/// These aren't hypothetical. The web app has no dark mode at all, so every
/// dark value here is new and unreviewed; and 522 hadith carry an attribution
/// over 250 characters, which is exactly the kind of content that looks fine
/// until someone opens the wrong narration.
final class AppearanceTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// The app opens on the search canvas, so anything that wants the daily
    /// hadith has to go a tab across first.
    @discardableResult
    private func openToday(_ app: XCUIApplication) -> Bool {
        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The search canvas never appeared"
        )
        tap(app.tabButton("Today"), "the Today tab", in: app)
        return app.staticTexts["Read in full"].waitForExistence(timeout: 20)
    }

    /// Fails loudly if the simulator wasn't put into the appearance this test
    /// is about. Without this the test would happily pass in light mode and
    /// attach a set of screenshots proving nothing.
    private func assertAppearance(_ app: XCUIApplication, isDark: Bool) {
        let expected = isDark ? "appearance-dark" : "appearance-light"
        XCTAssertTrue(
            app.descendants(matching: .any)[expected].waitForExistence(timeout: 20),
            "Simulator is not in \(isDark ? "dark" : "light") mode. Run scripts/uitest.sh, "
            + "or: xcrun simctl ui booted appearance \(isDark ? "dark" : "light")"
        )
    }

    override func setUp() {
        continueAfterFailure = false
    }

    func testDarkMode() {
        let app = launch()
        assertAppearance(app, isDark: true)
        capture(app, "dark-00-search-canvas")
        XCTAssertTrue(openToday(app), "The Today tab never showed a hadith of the day")
        capture(app, "dark-01-today")

        app.staticTexts["Read in full"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        capture(app, "dark-02-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app.tabButton("Browse"), "the Browse tab", in: app)
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari"].waitForExistence(timeout: 10))
        capture(app, "dark-03-browse")

        search(app, "kindness to neighbours")
        capture(app, "dark-04-search")
    }

    /// The largest accessibility size is where fixed-height rows, truncated
    /// badges, and hard-coded padding fall apart. Set by `scripts/uitest.sh`;
    /// running this directly just exercises whatever size the simulator is on.
    func testLargestDynamicType() {
        let app = launch()
        capture(app, "xxxl-00-search-canvas")
        XCTAssertTrue(openToday(app))
        capture(app, "xxxl-01-today")

        tap(app.tabButton("Browse"), "the Browse tab", in: app)
        XCTAssertTrue(app.staticTexts["Sahih al-Bukhari"].waitForExistence(timeout: 10))
        capture(app, "xxxl-02-browse")

        search(app, "kindness to neighbours")
        capture(app, "xxxl-03-search")
    }

    /// Muwatta 1467 has a 5,323-character attribution — the longest in the
    /// corpus by a wide margin. It is the worst case for the detail layout.
    func testLongestAttribution() {
        let app = launch()
        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The search canvas never appeared"
        )

        tap(app.tabButton("Browse"), "the Browse tab", in: app)
        XCTAssertTrue(app.staticTexts["Muwatta Malik"].waitForExistence(timeout: 10))
        app.staticTexts["Muwatta Malik"].tap()

        // Chapter 33 of 61, and hadith 1467 sits deep inside it. Both live in
        // lazy stacks, so they don't exist as elements until scrolled into view.
        let chapter = app.staticTexts["Sharecropping"]
        XCTAssertTrue(scrollToFind(chapter, in: app), "Expected a Sharecropping chapter in Muwatta")
        chapter.tap()

        let target = app.staticTexts["Muwatta Malik 1467"]
        XCTAssertTrue(scrollToFind(target, in: app), "Expected Muwatta 1467 in the Sharecropping chapter")
        capture(app, "long-01-card")

        target.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        capture(app, "long-02-detail")
    }

    /// Scrolls until `element` both exists and is on screen.
    ///
    /// `waitForExistence` isn't enough for lazy stacks: SwiftUI hasn't
    /// instantiated off-screen rows, so the element genuinely doesn't exist yet
    /// and no amount of waiting will conjure it.
    private func scrollToFind(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 25
    ) -> Bool {
        let scroll = app.scrollViews.firstMatch
        guard scroll.waitForExistence(timeout: 10) else { return false }

        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            scroll.swipeUp(velocity: .fast)
        }
        return element.exists && element.isHittable
    }

    private func search(_ app: XCUIApplication, _ text: String) {
        tap(app.searchTabButton, "the Search tab", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "%")).firstMatch
                .waitForExistence(timeout: 30),
            "No results for “\(text)”"
        )
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
