//
//  ShiftyUITests.swift
//  ShiftyUITests
//

import XCTest

final class ShiftyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Walks the first-launch flow and every tab, attaching screenshots
    /// for visual review.
    @MainActor
    func testWalkthrough() throws {
        let app = XCUIApplication()
        app.launch()

        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // Onboarding appears on first launch only.
        let jobField = app.textFields["Job name (e.g. Cafe)"]
        if jobField.waitForExistence(timeout: 5) {
            shot("01-onboarding")
            jobField.tap()
            // Return advances focus to the rate field via onSubmit.
            jobField.typeText("Cafe\n")
            app.typeText("20")
            // Drag down to dismiss the keyboard so Get Started is hittable.
            app.swipeDown()
            let getStarted = app.buttons["Get Started"]
            XCTAssertTrue(getStarted.waitForExistence(timeout: 3))
            getStarted.tap()
        }

        XCTAssertTrue(
            app.navigationBars["Shifty"].waitForExistence(timeout: 5),
            "Home should appear after onboarding"
        )
        shot("02-home-empty")

        // Log a shift with the default times.
        app.buttons["Add Shift"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Shift form should appear")
        shot("03-shift-form")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Shifty"].waitForExistence(timeout: 5))
        shot("04-home-with-shift")

        // Visit every tab. sidebarAdaptable keeps an offscreen sidebar copy
        // of each tab button, so prefer the tab bar and require hittability.
        for (index, tab) in ["Shifts", "Calendar", "Pay", "Settings"].enumerated() {
            let inTabBar = app.tabBars.buttons[tab].firstMatch
            let tabButton: XCUIElement
            if inTabBar.waitForExistence(timeout: 2) {
                tabButton = inTabBar
            } else {
                tabButton = app.buttons.matching(identifier: tab)
                    .allElementsBoundByIndex.first(where: \.isHittable)
                    ?? app.buttons[tab].firstMatch
            }
            XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "\(tab) tab should exist")
            tabButton.tap()
            XCTAssertTrue(
                app.navigationBars[tab].waitForExistence(timeout: 5),
                "\(tab) screen should appear"
            )
            shot("0\(5 + index)-\(tab.lowercased())")
        }
    }
}
