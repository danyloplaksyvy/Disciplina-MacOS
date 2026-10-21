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
        app.windows["main"].menuItems["Delete"].click()
        XCTAssertFalse(app.staticTexts["Updated task"].exists)
        app.buttons["Undo"].click()
        XCTAssertTrue(app.staticTexts["Updated task"].exists)
        app.staticTexts["Updated task"].rightClick()
        app.windows["main"].menuItems["Delete"].click()
        expectMenuBarStatus("Disciplina: All clear")
    }

    func testDeletionSupportsCommandZ() {
        add("Undo target")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Undo target"].click()
        list.staticTexts["Undo target"].rightClick()
        app.windows["main"].menuItems["Delete"].click()
        XCTAssertFalse(list.staticTexts["Undo target"].exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(list.staticTexts["Undo target"].waitForExistence(timeout: 3))
    }

    func testTextUndoKeepsDeletionHistorySeparate() {
        add("Deleted task")
        app.staticTexts["Deleted task"].rightClick()
        app.windows["main"].menuItems["Delete"].click()
        let input = app.textFields["new-task"]
        input.click()
        input.typeText("Draft")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(input.value as? String, "")
        XCTAssertFalse(app.staticTexts["Deleted task"].exists)
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
        app.typeText("Captured task\n")
        XCTAssertTrue(app.staticTexts["Captured task"].waitForExistence(timeout: 3))
    }

    func testGlobalCaptureFromFinderAndRepeatedShortcut() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--enable-test-shortcut"]
        app.launch()
        XCTAssertTrue(app.textFields["new-task"].waitForExistence(timeout: 10))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey(" ", modifierFlags: [.control, .option])
        let capture = app.textFields["capture-task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        app.typeText("From Finder")
        app.typeKey(" ", modifierFlags: [.control, .option])
        XCTAssertEqual(capture.value as? String, "From Finder")
        app.typeText(" captured\n")
        app.activate()
        XCTAssertTrue(app.staticTexts["From Finder captured"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "From Finder captured").count, 1)
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

    func testTimerLabelAndPauseRestoreCount() {
        add("Timed task")
        app.buttons["Start Timed task"].click()
        expectMenuBarStatus("Disciplina: Timing Timed task")
        attachMenuBarScreenshot("running-timer-dot")
        let appearance = XCTAttachment(screenshot: app.windows["main"].screenshot())
        appearance.name = "main-window-running-timer"
        appearance.lifetime = .keepAlways
        add(appearance)
        app.statusItems.firstMatch.click()
        attachMenuBarScreenshot("running-timer-selected")
        XCTAssertTrue(app.buttons["Open Disciplina"].waitForExistence(timeout: 3))
        app.statusItems.firstMatch.click()
        app.buttons["Pause Timed task"].click()
        expectMenuBarStatus("Disciplina: 1 active task")
        XCTAssertTrue(app.buttons["Resume Timed task"].exists)
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
        app.buttons["Open Disciplina"].click()
        XCTAssertTrue(app.buttons["Reopen Shared task"].waitForExistence(timeout: 3))
    }
    func testDetailsLayoutAndSessionEditing() {
        add("A long task title that must remain readable while its details are open")
        let list = app.outlines["main-task-list"]
        list.staticTexts.firstMatch.click()
        // Open explicitly rather than relying on which section header is first.
        list.staticTexts["A long task title that must remain readable while its details are open"].click()
        let close = app.buttons["Close details"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(list.frame.width, 360)
        let snapshot = XCTAttachment(screenshot: app.windows["main"].screenshot())
        snapshot.name = "readable-task-details"; snapshot.lifetime = .keepAlways; add(snapshot)
        app.buttons["Add time…"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        let minutes = sheet.textFields["duration-minutes"]
        minutes.click(); minutes.typeKey("a", modifierFlags: .command); minutes.typeText("2")
        sheet.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Manually added"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["00:02:00"].firstMatch.exists)
        app.buttons["Edit duration"].click()
        let editMinutes = app.sheets.firstMatch.textFields["duration-minutes"]
        editMinutes.click(); editMinutes.typeKey("a", modifierFlags: .command); editMinutes.typeText("1")
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["00:02:00"].firstMatch.exists)
        app.buttons["Edit duration"].click()
        let savedMinutes = app.sheets.firstMatch.textFields["duration-minutes"]
        savedMinutes.click(); savedMinutes.typeKey("a", modifierFlags: .command); savedMinutes.typeText("1")
        app.sheets.firstMatch.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["00:01:00"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Delete session…"].click()
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Manually added"].exists)
        app.buttons["Delete session…"].click()
        app.buttons["Delete session"].click()
        XCTAssertTrue(app.staticTexts["No work sessions yet."].waitForExistence(timeout: 3))
        close.click()
        XCTAssertFalse(close.exists)
        XCTAssertGreaterThan(list.frame.width, 650)
    }

    func testOpeningTimeEditorPausesAndCancelDoesNotResume() {
        add("Pause for editing")
        app.buttons["Start Pause for editing"].click()
        expectMenuBarStatus("Disciplina: Timing Pause for editing")
        app.outlines["main-task-list"].staticTexts["Pause for editing"].click()
        app.buttons["Add time…"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
        expectMenuBarStatus("Disciplina: 1 active task")
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Resume Pause for editing"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Pause Pause for editing"].exists)
    }

    func testPopoverAcceptsTypingOverAnotherApplication() {
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        app.statusItems.firstMatch.click()
        XCTAssertTrue(app.buttons["Open Disciplina"].waitForExistence(timeout: 3))
        app.typeText("Popover focused without clicking\n")
        let popoverList = app.descendants(matching: .any)["popover-task-list"].firstMatch
        XCTAssertTrue(popoverList.staticTexts["Popover focused without clicking"].waitForExistence(timeout: 3))
        app.statusItems.firstMatch.click()
    }

}
