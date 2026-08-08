import XCTest

/// Finds the tab controls without assuming how the platform draws them.
///
/// On iPhone a `TabView` is a bottom tab bar and its items are
/// `app.tabBars.buttons`. On iPad, iOS 26 renders the same `TabView` as a
/// segmented control mounted in the top bar, so `app.tabBars` matches nothing
/// at all. Both are the same app and the same code — only the query differs,
/// which is exactly the kind of thing that should live in one helper rather
/// than being duplicated (and half-forgotten) across tests.
extension XCUIApplication {
    /// Every query is resolved with `firstMatch`. On iPad the selected tab's
    /// name also appears as the navigation title, so a bare `buttons[label]`
    /// lookup is ambiguous and throws rather than picking one.
    func tabButton(_ label: String) -> XCUIElement {
        let candidates = [
            tabBars.buttons[label],
            segmentedControls.buttons[label],
            navigationBars.buttons[label],
            toolbars.buttons[label],
        ]
        for candidate in candidates where candidate.firstMatch.exists {
            return candidate.firstMatch
        }
        return buttons.matching(identifier: label).firstMatch
    }

    /// The tab with `role: .search`. It carries no visible title, so it can't be
    /// looked up by label the way the others can.
    var searchTabButton: XCUIElement {
        let bar = tabBars.firstMatch
        if bar.exists, bar.buttons.count > 0 {
            return bar.buttons.element(boundBy: bar.buttons.count - 1)
        }
        let named = buttons["Search"]
        if named.exists { return named }
        return descendants(matching: .button)
            .matching(NSPredicate(format: "label CONTAINS[c] 'search'"))
            .firstMatch
    }

    /// Attaches the element tree so a failed lookup says what was actually on
    /// screen instead of just "no matches found".
    func hierarchyDescription() -> String { debugDescription }
}

extension XCTestCase {
    func tap(_ element: XCUIElement, _ what: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        guard element.waitForExistence(timeout: timeout) else {
            let dump = XCTAttachment(string: app.hierarchyDescription())
            dump.name = "hierarchy-when-\(what)-not-found"
            dump.lifetime = .keepAlways
            add(dump)
            XCTFail("Couldn't find \(what) — element hierarchy attached")
            return
        }
        element.tap()
    }
}
