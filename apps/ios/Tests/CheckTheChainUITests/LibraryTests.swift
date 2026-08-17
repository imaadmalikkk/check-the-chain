import XCTest

/// The only test that proves persistence.
///
/// A favourites feature can pass every in-process unit test and still lose
/// everything on a cold launch — the store never gets written, or gets written
/// somewhere that does not survive the process. Nothing else in the suite would
/// notice, so this terminates the app and starts it again.
final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSavedHadithSurvivesRelaunch() {
        var app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The search canvas never appeared"
        )

        // Bukhari 1 is reached through Browse, which is a known-stable path.
        tap(app.tabButton("Browse"), "the Browse tab", in: app)
        XCTAssertTrue(
            app.staticTexts["Sahih al-Bukhari"].waitForExistence(timeout: 10),
            "Sahih al-Bukhari never appeared in the collection list"
        )
        app.staticTexts["Sahih al-Bukhari"].tap()
        XCTAssertTrue(
            app.staticTexts["Revelation"].waitForExistence(timeout: 10),
            "Revelation never appeared in Bukhari's chapter list"
        )
        app.staticTexts["Revelation"].tap()
        XCTAssertTrue(
            app.staticTexts["Sahih al-Bukhari 1"].waitForExistence(timeout: 10),
            "Sahih al-Bukhari 1 never appeared in the Revelation chapter"
        )
        app.staticTexts["Sahih al-Bukhari 1"].tap()

        let star = app.buttons["saveToggle"]
        XCTAssertTrue(star.waitForExistence(timeout: 10), "No save button on the detail page")
        star.tap()

        app.terminate()

        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["check the chain"].waitForExistence(timeout: 20),
            "The app did not come back up"
        )

        let library = app.buttons["libraryButton"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "No library button after relaunch")
        library.tap()

        XCTAssertTrue(
            app.staticTexts["Sahih al-Bukhari 1"].waitForExistence(timeout: 15),
            "The starred hadith did not survive a cold launch"
        )
    }
}
