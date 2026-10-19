import XCTest

@MainActor
final class DisciplinaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.textFields["new-task"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws { app.terminate() }

    private func add(_ title: String) {
        let field = app.textFields["new-task"]
        field.click(); field.typeText(title + "\n")
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "")
    }

    private func expectMenuBarStatus(_ label: String) {
        let status = app.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        // AppKit can expose a status button's accessible name as its title instead of label.
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ OR title == %@", label, label), object: status)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        attachMenuBarScreenshot("status-\(label)")
        XCTAssertEqual(result, .completed, status.debugDescription)
        // An icon-only fallback is about 24 pt wide. Text must actually be rendered.
        XCTAssertGreaterThan(status.frame.width, 50)
    }

    private func attachMenuBarScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.statusItems.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCreateEditCompleteReopenDelete() {
        expectMenuBarStatus("Disciplina: All clear")
        attachMenuBarScreenshot("menu-bar-all-clear")
        add("UI task")
        expectMenuBarStatus("Disciplina: 1 active task")
        attachMenuBarScreenshot("menu-bar-one-task")
        app.staticTexts["UI task"].doubleClick()
        let edit = app.textFields["edit-task"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.typeKey("a", modifierFlags: .command)
        edit.typeText("Updated task\n")
        expectMenuBarStatus("Disciplina: 1 active task")
        app.buttons["Complete Updated task"].click()
        expectMenuBarStatus("Disciplina: All clear")
        XCTAssertTrue(app.buttons["Reopen Updated task"].waitForExistence(timeout: 3))
        app.buttons["Reopen Updated task"].click()
        expectMenuBarStatus("Disciplina: 1 active task")
        app.staticTexts["Updated task"].rightClick()
        app.menuItems["Delete…"].click()
        app.windows["main"].sheets.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Updated task"].exists)
        app.staticTexts["Updated task"].rightClick()
        app.menuItems["Delete…"].click()
        app.windows["main"].sheets.buttons["Delete"].click()
        XCTAssertFalse(app.staticTexts["Updated task"].exists)
        expectMenuBarStatus("Disciplina: All clear")
    }

    func testCancelEditingAndCapture() {
        add("Original title")
        app.staticTexts["Original title"].doubleClick()
        let edit = app.textFields["edit-task"]
        edit.typeKey("a", modifierFlags: .command)
        edit.typeText("Discard this")
        edit.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Original title"].exists)
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Quick Capture"].click()
        let capture = app.textFields["capture-task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.typeText("Unsaved capture")
        capture.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.staticTexts["Unsaved capture"].exists)
    }

    func testCaptureSavesIntoMainWindow() {
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Quick Capture"].click()
        let capture = app.textFields["capture-task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.typeText("Captured task\n")
        XCTAssertTrue(app.staticTexts["Captured task"].waitForExistence(timeout: 3))
    }

    func testCloseAndReopenSingleWindow() {
        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(app.windows["main"].exists)
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Open Task Window"].click()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 3))
        app.typeKey("o", modifierFlags: .command)
        XCTAssertEqual(app.windows.matching(identifier: "main").count, 1)
    }

    func testMenuBarCountCrossesDigitBoundaryWhileClosed() {
        for index in 1...9 { add("Task \(index)") }
        expectMenuBarStatus("Disciplina: 9 active tasks")
        attachMenuBarScreenshot("menu-bar-nine-tasks")
        add("Tenth task")
        expectMenuBarStatus("Disciplina: 10 active tasks")
        attachMenuBarScreenshot("menu-bar-ten-tasks")
        app.statusItems.firstMatch.click()
        let list = app.descendants(matching: .any)["popover-task-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        attachMenuBarScreenshot("menu-bar-selected")
    }

    func testMainAndPopoverShareTasks() throws {
        add("Shared task")
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5), "Menu bar status item must be available")
        statusItem.click()
        let list = app.descendants(matching: .any)["popover-task-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertTrue(list.staticTexts["Shared task"].exists)
        list.buttons["Complete Shared task"].click()
        app.buttons["Open full app"].click()
        XCTAssertTrue(app.buttons["Reopen Shared task"].waitForExistence(timeout: 3))
    }
}
