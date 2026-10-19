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

    func testCreateEditCompleteReopenDelete() {
        add("UI task")
        app.staticTexts["UI task"].doubleClick()
        let edit = app.textFields["edit-task"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.typeKey("a", modifierFlags: .command)
        edit.typeText("Updated task\n")
        app.buttons["Complete Updated task"].click()
        XCTAssertTrue(app.buttons["Reopen Updated task"].waitForExistence(timeout: 3))
        app.buttons["Reopen Updated task"].click()
        app.staticTexts["Updated task"].rightClick()
        app.menuItems["Delete…"].click()
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Updated task"].exists)
        app.staticTexts["Updated task"].rightClick()
        app.menuItems["Delete…"].click()
        app.buttons["Delete"].click()
        XCTAssertFalse(app.staticTexts["Updated task"].exists)
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
