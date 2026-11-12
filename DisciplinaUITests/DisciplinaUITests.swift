import XCTest

@MainActor
final class DisciplinaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.outlines["today-task-list"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigate-today"].exists)
        app.radioButtons["All tasks"].click()
        XCTAssertTrue(app.textFields["new-task"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws { app.terminate() }

    func testTodayCreationCompletionRemovalAndUndo() {
        selectTaskScope("Today")
        let list = app.outlines["today-task-list"]
        add("Plan work")
        XCTAssertTrue(list.staticTexts["Plan work"].exists)
        list.buttons["Complete Plan work"].click()
        XCTAssertTrue(app.buttons["Expand planned completed"].waitForExistence(timeout: 5))
        app.buttons["Expand planned completed"].click()
        list.buttons["Reopen Plan work"].click()
        list.staticTexts["Plan work"].click()
        clickDetailButton("Remove from plan")
        XCTAssertFalse(list.staticTexts["Plan work"].exists)
        XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Plan work"].exists)
        clickDetailButton("Add to Today")
        XCTAssertTrue(list.staticTexts["Plan work"].waitForExistence(timeout: 5))
        app.buttons["Close details"].click()
        list.staticTexts["Plan work"].rightClick()
        app.windows["main"].menuItems["Delete"].click()
        XCTAssertFalse(list.staticTexts["Plan work"].exists)
        app.buttons["Undo"].firstMatch.click()
        XCTAssertTrue(list.staticTexts["Plan work"].waitForExistence(timeout: 5))
    }

    func testCommandFFromTodayPreservesDetails() {
        add("Existing work")
        selectTaskScope("Today")
        XCTAssertFalse(app.outlines["today-task-list"].staticTexts["Existing work"].exists)
        app.buttons["Add existing task…"].click()
        let sheet = app.sheets.firstMatch
        sheet.searchFields["task-search"].typeText("existing")
        sheet.buttons["Add Existing work to Today"].click()
        let list = app.outlines["today-task-list"]
        XCTAssertTrue(list.staticTexts["Existing work"].waitForExistence(timeout: 5))
        list.staticTexts["Existing work"].click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertEqual(app.radioButtons["All tasks"].value.map { String(describing: $0) }, "1")
        XCTAssertTrue(app.outlines["main-task-list"].waitForExistence(timeout: 5))
        taskSearch.typeText("Existing")
        selectTaskScope("Today")
        XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Existing work"].exists)
        XCTAssertTrue(list.staticTexts["Existing work"].exists)
        for _ in 0..<3 {
            app.typeKey("f", modifierFlags: .command)
            taskSearch.typeKey("a", modifierFlags: .command)
            taskSearch.typeText("Existing")
            XCTAssertEqual(taskSearch.value as? String, "Existing")
            selectTaskScope("Today")
            XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Existing work"].exists)
        }
    }

    func testTodayReorderingAndCompactDetails() {
        selectTaskScope("Today")
        add("First plan"); add("Second plan")
        let list = app.outlines["today-task-list"]
        XCTAssertLessThan(list.staticTexts["First plan"].frame.minY, list.staticTexts["Second plan"].frame.minY)
        list.staticTexts["Second plan"].rightClick()
        app.windows["main"].menuItems["Move Up"].click()
        XCTAssertLessThan(list.staticTexts["Second plan"].frame.minY, list.staticTexts["First plan"].frame.minY)
        let window = app.windows["main"]
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: 780 - window.frame.width, dy: -80)))
        XCTAssertTrue(app.menuButtons["compact-navigation"].waitForExistence(timeout: 5))
        list.staticTexts["First plan"].click()
        XCTAssertGreaterThanOrEqual(list.frame.width, 360)
        XCTAssertGreaterThanOrEqual(app.scrollViews["task-details"].frame.width, 300)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "today-compact-details"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func selectTaskScope(_ title: String) {
        let control = app.radioButtons[title]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.click()
    }

    func testTaskScopesPreserveCreationDraftDetailsAndQueries() {
        add("Unplanned work")
        app.outlines["main-task-list"].staticTexts["Unplanned work"].click()
        let field = app.textFields["new-task"]
        field.click(); field.typeText("Draft for today")
        taskSearch.click(); taskSearch.typeText("Unplanned")
        selectTaskScope("Today")
        XCTAssertEqual(field.value as? String, "Draft for today")
        XCTAssertEqual(taskSearch.value as? String, "")
        XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Unplanned work"].exists)
        XCTAssertTrue(app.staticTexts["filtered-details-notice"].exists)
        field.click(); field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.outlines["today-task-list"].staticTexts["Draft for today"].waitForExistence(timeout: 5))
        selectTaskScope("All tasks")
        XCTAssertEqual(taskSearch.value as? String, "Unplanned")
        XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Unplanned work"].exists)
        app.typeKey("f", modifierFlags: .command)
        taskSearch.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.outlines["main-task-list"].staticTexts["Draft for today"].waitForExistence(timeout: 5))
    }

    func testTodayFiltersPreventPartialReorderingAndPreserveRenameDraft() {
        selectTaskScope("Today")
        add("Plan Alpha"); add("Plan Beta")
        let list = app.outlines["today-task-list"]
        list.staticTexts["Plan Alpha"].rightClick()
        app.windows["main"].menuItems["Edit title"].click()
        let editor = app.textFields["edit-task"]
        editor.typeKey("a", modifierFlags: .command); editor.typeText("Uncommitted title")
        selectTaskScope("All tasks")
        XCTAssertEqual(app.textFields["edit-task"].value as? String, "Uncommitted title")
        selectTaskScope("Today")
        XCTAssertEqual(app.textFields["edit-task"].value as? String, "Uncommitted title")
        app.buttons["Cancel"].firstMatch.click()
        taskSearch.click(); taskSearch.typeText("Beta")
        list.staticTexts["Plan Beta"].rightClick()
        XCTAssertFalse(app.windows["main"].menuItems["Move Up"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["Clear filters"].click()
        list.staticTexts["Plan Beta"].rightClick()
        XCTAssertTrue(app.windows["main"].menuItems["Move Up"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func add(_ title: String) {
        let field = app.textFields["new-task"]
        field.click(); field.typeText(title)
        XCTAssertEqual(field.value as? String, title)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "")
    }

    private func clickDetailButton(_ label: String) {
        let pane = app.scrollViews["task-details"]
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            let frame = button.frame
            if frame.minY >= pane.frame.minY && frame.maxY <= pane.frame.maxY { break }
            pane.scroll(byDeltaX: 0, deltaY: frame.midY > pane.frame.midY ? -150 : 150)
        }
        button.click()
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

    private func openGoals() {
        let button = app.buttons["navigate-goals"].firstMatch
        if button.exists && button.isHittable { button.click() }
        else {
            app.menuButtons["compact-navigation"].click()
            app.menuItems["Goals"].click()
        }
        XCTAssertTrue(app.buttons["New Goal"].waitForExistence(timeout: 5))
    }
    private func createGoal(_ title: String) {
        app.buttons["New Goal"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.textFields["goal-title"].click(); sheet.textFields["goal-title"].typeText(title)
        let criterion = sheet.textViews["goal-criteria"]
        criterion.click(); criterion.typeText("A verified outcome")
        sheet.buttons["Save"].click()
        XCTAssertTrue(app.scrollViews["goal-details"].waitForExistence(timeout: 5))
    }
    private func goalButton(_ label: String) -> XCUIElement {
        let pane = app.scrollViews["goal-details"]
        let button = pane.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<15 {
            let frame = button.frame
            if frame.minY >= pane.frame.minY && frame.maxY <= pane.frame.maxY { break }
            pane.scroll(byDeltaX: 0, deltaY: frame.midY > pane.frame.midY ? -180 : 180)
        }
        return button
    }
    func testGoalsMilestonesLifecycleAndUndo() {
        openGoals(); createGoal("Launch project")
        goalButton("Add Milestone").click()
        var sheet = app.sheets.firstMatch
        sheet.textFields["milestone-title"].typeText("First release")
        sheet.buttons["Save"].click()
        goalButton("Complete milestone First release").click()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "1 of 1 milestones completed")).firstMatch.waitForExistence(timeout: 5))
        goalButton("Mark Achieved").click()
        XCTAssertTrue(app.buttons["Reopen Goal"].exists)
        goalButton("Archive Goal").click(); goalButton("Restore Goal").click()
        XCTAssertTrue(app.buttons["Reopen Goal"].exists)
        goalButton("Reopen Goal").click()
        let menu = app.scrollViews["goal-details"].menuButtons["Actions for milestone First release"]
        menu.click(); app.menuItems["Delete Milestone"].click()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "No milestones defined")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["First release"].waitForExistence(timeout: 5))
        goalButton("Edit Goal").click()
        sheet = app.sheets.firstMatch
        sheet.textFields["goal-title"].click(); sheet.textFields["goal-title"].typeKey("a", modifierFlags: .command)
        sheet.textFields["goal-title"].typeText("Cancelled title")
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Launch project"].exists)
        XCTAssertFalse(app.staticTexts["Cancelled title"].exists)
        let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
        attachment.name = "goals-milestones"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testGoalTaskCreationAttributionAndPauseBeforeUnlinking() {
        openGoals(); createGoal("Learn Swift")
        let pane = app.scrollViews["goal-details"]
        let field = pane.textFields["new-task"]
        for _ in 0..<8 {
            if field.exists && field.frame.minY >= pane.frame.minY && field.frame.maxY <= pane.frame.maxY { break }
            pane.scroll(byDeltaX: 0, deltaY: -150)
        }
        field.click(); field.typeText("Practice Swift\n")
        XCTAssertTrue(pane.staticTexts["Practice Swift"].waitForExistence(timeout: 5))
        goalButton("Start Practice Swift").click()
        pane.staticTexts["Practice Swift"].click()
        XCTAssertTrue(app.scrollViews["task-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Goal: Learn Swift"].firstMatch.exists)
        clickDetailButton("Change Goal…")
        let sheet = app.sheets.firstMatch
        sheet.popUpButtons["goal-picker"].click(); app.menuItems["Unassigned"].click()
        sheet.buttons["Save"].click()
        XCTAssertTrue(app.buttons["Pause and Continue"].waitForExistence(timeout: 5))
        app.windows["main"].sheets.buttons["Pause and Continue"].firstMatch.click()
        XCTAssertTrue(app.buttons["Resume Practice Swift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Goal: Unassigned"].exists)
        XCTAssertTrue(app.staticTexts["Goal: Learn Swift"].exists)
        app.buttons["goals-back"].click()
        XCTAssertFalse(app.scrollViews["goal-details"].staticTexts["Practice Swift"].exists)
        app.buttons["navigate-tasks"].firstMatch.click()
        XCTAssertTrue(app.outlines["main-task-list"].staticTexts["Practice Swift"].exists)
    }
    func testGoalsValidationAndNavigationPreserveTaskSelection() {
        add("Keep selection")
        app.outlines["main-task-list"].staticTexts["Keep selection"].click()
        openGoals(); app.buttons["New Goal"].click()
        let sheet = app.sheets.firstMatch
        sheet.buttons["Save"].click()
        XCTAssertTrue(sheet.staticTexts["goal-editor-error"].waitForExistence(timeout: 5))
        sheet.buttons["Cancel"].click()
        app.buttons["navigate-tasks"].firstMatch.click()
        XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Keep selection"].exists)
        XCTAssertGreaterThanOrEqual(app.outlines["main-task-list"].frame.width, 360)
        XCTAssertGreaterThanOrEqual(app.scrollViews["task-details"].frame.width, 300)
        XCTAssertEqual(app.statusItems.count, 1)
    }

    func testHundredGoalsWithHundredTasksRemainNavigable() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--seed-goals-performance"]
        app.launch()
        XCTAssertTrue(app.textFields["new-task"].firstMatch.waitForExistence(timeout: 60))
        selectTaskScope("All tasks")
        openGoals()
        let goal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open goal Performance Goal")).firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 5)); goal.click()
        XCTAssertTrue(app.scrollViews["goal-details"].waitForExistence(timeout: 5))
        let start = app.scrollViews["goal-details"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start Work")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let label = start.label
        goalButton(label).click()
        let pause = app.buttons[label.replacingOccurrences(of: "Start ", with: "Pause ")]
        XCTAssertTrue(pause.waitForExistence(timeout: 10)); pause.click()
        XCTAssertTrue(app.buttons[label.replacingOccurrences(of: "Start ", with: "Resume ")].waitForExistence(timeout: 10))
        app.buttons["navigate-tasks"].firstMatch.click()
        XCTAssertTrue(app.outlines["main-task-list"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(taskSearch.waitForExistence(timeout: 5))
        taskSearch.typeText("Work 42-")
        XCTAssertTrue(app.staticTexts["100 of 10000 tasks · Local storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.outlines["main-task-list"].staticTexts["Work 42-0"].exists)
        let list = app.outlines["main-task-list"]
        // Scroll position is exposed by the native scroll bar; no off-screen row lookup.
        let scrollView = app.scrollViews.containing(.outline, identifier: "main-task-list").firstMatch
        list.scroll(byDeltaX: 0, deltaY: -500)
        let scrollBar = scrollView.scrollBars.firstMatch
        XCTAssertTrue(scrollBar.waitForExistence(timeout: 5))
        let position = scrollBar.value.map { String(describing: $0) }
        XCTAssertNotNil(position)
        selectTaskScope("Today"); selectTaskScope("All tasks")
        XCTAssertEqual(taskSearch.value as? String, "Work 42-")
        XCTAssertEqual(scrollBar.value.map { String(describing: $0) }, position)

    }

    private var taskSearch: XCUIElement { app.searchFields["task-search"].firstMatch }

    func testSearchRestoresDayExpansionAndSurvivesNavigationAndWindowReopen() {
        add("Alpha task"); add("Beta task")
        let list = app.outlines["main-task-list"]
        list.buttons["Collapse Today"].click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(taskSearch.waitForExistence(timeout: 5))
        taskSearch.typeText("alpha")
        XCTAssertTrue(list.staticTexts["Alpha task"].waitForExistence(timeout: 5))
        XCTAssertFalse(list.staticTexts["Beta task"].exists)
        openGoals()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertEqual(taskSearch.value as? String, "alpha")
        app.windows["main"].buttons[XCUIIdentifierCloseWindow].click()
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(taskSearch.waitForExistence(timeout: 5))
        XCTAssertEqual(taskSearch.value as? String, "alpha")
        taskSearch.click(); taskSearch.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(taskSearch.value as? String, "")
        XCTAssertTrue(list.buttons["Expand Today"].exists)
        XCTAssertFalse(list.staticTexts["Alpha task"].exists)
        taskSearch.typeKey(.escape, modifierFlags: [])
        list.buttons["Expand Today"].click()
        XCTAssertTrue(list.staticTexts["Beta task"].exists)
    }

    func testSearchKeepsHiddenDetailsAndInlineDraft() {
        add("Alpha original"); add("Beta task")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Alpha original"].click()
        list.staticTexts["Alpha original"].rightClick()
        app.menuItems["Edit title"].click()
        let editor = app.textFields["edit-task"]
        editor.click(); editor.typeKey("a", modifierFlags: .command); editor.typeText("Unfinished title")
        XCTAssertEqual(editor.value as? String, "Unfinished title")
        app.typeKey("f", modifierFlags: .command); taskSearch.typeText("Beta")
        XCTAssertTrue(app.staticTexts["filtered-details-notice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["task-details"].staticTexts["Alpha original"].exists)
        XCTAssertFalse(editor.exists)
        taskSearch.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Unfinished title")
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(list.staticTexts["Alpha original"].exists)
    }

    func testCombinedFiltersAndHiddenCreation() {
        add("Finished task"); add("Open task")
        let list = app.outlines["main-task-list"]
        list.buttons["Complete Finished task"].click()
        app.popUpButtons["task-status-filter"].click(); app.menuItems["Completed"].click()
        XCTAssertTrue(list.staticTexts["Finished task"].exists)
        XCTAssertFalse(list.staticTexts["Open task"].exists)
        app.popUpButtons["task-goal-filter"].click(); app.menuItems["Unassigned"].click()
        app.typeKey("f", modifierFlags: .command); taskSearch.typeText("Finished")
        XCTAssertTrue(list.staticTexts["Finished task"].exists)
        let input = app.textFields["new-task"]
        input.click(); input.typeText("Hidden new task"); input.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.otherElements["filtered-creation-notice"].exists || app.staticTexts["Created “Hidden new task”. It is hidden by the current filters."].waitForExistence(timeout: 5))
        XCTAssertFalse(list.staticTexts["Hidden new task"].exists)
        app.buttons["Clear filters"].firstMatch.click()
        XCTAssertTrue(list.staticTexts["Hidden new task"].waitForExistence(timeout: 5))
        XCTAssertTrue(list.staticTexts["Open task"].exists)
        app.typeKey("f", modifierFlags: .command); taskSearch.typeText("Open")
        list.staticTexts["Open task"].rightClick(); app.windows["main"].menuItems["Delete"].click()
        XCTAssertFalse(list.staticTexts["Open task"].exists)
        app.buttons["Undo"].firstMatch.click()
        XCTAssertTrue(list.staticTexts["Open task"].waitForExistence(timeout: 5))
        XCTAssertEqual(taskSearch.value as? String, "Open")
    }

    func testSearchInResizedCompactWindowKeepsDetailsReadable() {
        add("Compact search task")
        let window = app.windows["main"]
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: 780 - window.frame.width, dy: -80)))
        XCTAssertLessThan(window.frame.width, 1000)
        XCTAssertTrue(app.menuButtons["compact-navigation"].waitForExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command); taskSearch.typeText("Compact")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Compact search task"].click()
        XCTAssertGreaterThanOrEqual(list.frame.width, 360)
        XCTAssertGreaterThanOrEqual(app.scrollViews["task-details"].frame.width, 300)
        XCTAssertTrue(taskSearch.isHittable)
        XCTAssertTrue(app.popUpButtons["task-status-filter"].isHittable)
        XCTAssertTrue(app.popUpButtons["task-goal-filter"].isHittable)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "compact-task-search"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func openActivity() {
        let button = app.buttons["navigate-activity"].firstMatch
        if button.exists && button.isHittable {
            // Exercise the trailing empty area, not just the text or symbol.
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).click()
        } else {
            app.menuButtons["compact-navigation"].click(); app.menuItems["Activity"].click()
        }
        XCTAssertTrue(app.buttons["activity-current-period"].waitForExistence(timeout: 5))
    }

    func testActivityCalendarWeeklyReviewAndFullRowNavigation() {
        add("Calendar work")
        app.outlines["main-task-list"].staticTexts["Calendar work"].click()
        clickDetailButton("Add time…")
        let sheet = app.windows["main"].sheets.firstMatch
        let minutes = sheet.textFields["duration-minutes"]
        minutes.click(); minutes.typeKey("a", modifierFlags: .command); minutes.typeText("1")
        sheet.buttons["Save"].click()
        openActivity()
        XCTAssertTrue(app.staticTexts["Manual or corrected"].waitForExistence(timeout: 5))
        let taskLink = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity-task-")).firstMatch
        XCTAssertTrue(taskLink.exists)
        app.buttons["Next month"].click(); app.buttons["activity-current-period"].click()
        let activityPane = app.scrollViews.containing(.button, identifier: taskLink.identifier).firstMatch
        for _ in 0..<12 {
            if taskLink.isHittable { break }
            print("Activity scroll: pane=\(activityPane.frame) task=\(taskLink.frame) bars=\(activityPane.scrollBars.debugDescription)")
            activityPane.scroll(byDeltaX: 0, deltaY: -150)
        }
        taskLink.click()
        XCTAssertTrue(app.scrollViews["task-details"].waitForExistence(timeout: 5))
        app.buttons["Back to Activity"].click()
        app.radioButtons["Weekly Review"].click()
        XCTAssertTrue(app.staticTexts["Currently completed during this week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["This Week"].exists)
    }

    func testOptionalTaskAppearanceSavesAndCancels() {
        add("Recognizable task")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Recognizable task"].click()
        clickDetailButton("Appearance…")
        let sheet = app.windows["main"].sheets.firstMatch
        sheet.popUpButtons["appearance-symbol"].click(); app.menuItems["Book"].click()
        sheet.buttons["Cancel"].click()
        XCTAssertFalse(list.images.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-symbol-")).firstMatch.exists)
        clickDetailButton("Appearance…")
        sheet.popUpButtons["appearance-symbol"].click(); app.menuItems["Book"].click()
        sheet.popUpButtons["appearance-color"].click(); app.menuItems["Blue"].click()
        sheet.buttons["Save"].click()
        XCTAssertTrue(list.images.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-symbol-")).firstMatch.waitForExistence(timeout: 5))
    }

    func testPopoverUndoAndDismissedUndoRemainsAvailable() {
        add("Recover from popover")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Recover from popover"].rightClick()
        app.windows["main"].menuItems["Delete"].click()
        app.statusItems.firstMatch.click()
        let popover = app.dialogs["status-panel"]
        XCTAssertTrue(popover.buttons["Undo"].waitForExistence(timeout: 5))
        popover.buttons["Undo"].click()
        XCTAssertTrue(popover.staticTexts["Recover from popover"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        list.staticTexts["Recover from popover"].rightClick()
        app.windows["main"].menuItems["Delete"].click()
        app.buttons["Dismiss deletion feedback"].click()
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(list.staticTexts["Recover from popover"].waitForExistence(timeout: 5))
    }

    func testLoginLaunchHasStatusItemWithoutMainWindow() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--simulate-login-launch"]
        app.launch()
        expectMenuBarStatus("Disciplina: All clear")
        XCTAssertFalse(app.windows["main"].isHittable)
        XCTAssertEqual(app.statusItems.count, 1)
        app.statusItems.firstMatch.click()
        let field = app.textFields["new-task"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("Login capture\n")
        XCTAssertTrue(app.staticTexts["Login capture"].waitForExistence(timeout: 5))
        app.buttons["Open Disciplina"].click()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.statusItems.count, 1)
    }

    func testLoginStorageRecoveryRetainsOneStatusItem() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--simulate-login-launch", "--simulate-storage-failure"]
        app.launch()
        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.windows["main"].isHittable)
        app.statusItems.firstMatch.click()
        XCTAssertTrue(app.staticTexts["Unable to open tasks"].waitForExistence(timeout: 5))
        app.buttons["Retry"].click()
        XCTAssertEqual(app.statusItems.count, 1)
        app.statusItems.firstMatch.click()
        XCTAssertTrue(app.textFields["new-task"].waitForExistence(timeout: 5))
    }

    func testDayCollapseAndRecurringTaskEditor() {
        add("Recurring practice")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Recurring practice"].click()
        app.buttons["Repeat…"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.popUpButtons.firstMatch.click()
        app.menuItems["Every day"].click()
        sheet.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Current occurrence"].waitForExistence(timeout: 5))
        app.buttons["Close details"].click()
        list.buttons["Collapse Today"].click()
        XCTAssertFalse(list.staticTexts["Recurring practice"].exists)
        list.buttons["Expand Today"].click()
        XCTAssertTrue(list.staticTexts["Recurring practice"].exists)
        list.buttons["Complete Recurring practice"].click()
        XCTAssertTrue(list.buttons["Reopen Recurring practice"].waitForExistence(timeout: 5))
        expectMenuBarStatus("Disciplina: All clear")
        list.buttons["Reopen Recurring practice"].click()
        expectMenuBarStatus("Disciplina: 1 active task")
        list.staticTexts["Recurring practice"].click()
        let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
        attachment.name = "selected-recurring-row"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testRecurringSeriesCanStopBetweenOccurrencesInSettings() {
        add("Scheduled practice")
        let list = app.outlines["main-task-list"]
        list.staticTexts["Scheduled practice"].click()
        app.buttons["Repeat…"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.popUpButtons.firstMatch.click(); app.menuItems["Every day"].click()
        sheet.buttons["Save"].click()
        list.buttons["Complete Scheduled practice"].click()
        app.buttons["Settings"].firstMatch.click()
        let stop = app.buttons["Stop repeating"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.click()
        XCTAssertTrue(app.staticTexts["No repeating tasks"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.outlines["today-task-list"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigate-today"].exists)
        selectTaskScope("All tasks")
        XCTAssertTrue(app.textFields["new-task"].waitForExistence(timeout: 10))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        app.statusItems.firstMatch.click()
        let statusPanel = app.dialogs["status-panel"]
        XCTAssertTrue(statusPanel.buttons["Open Disciplina"].waitForExistence(timeout: 3))
        finder.typeKey(" ", modifierFlags: [.control, .option])
        let capture = app.textFields["capture-task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        XCTAssertFalse(statusPanel.exists)
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
        app.windows["main"].textFields["new-task"].click()
        XCTAssertFalse(list.exists)
        statusItem.click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.buttons["Complete Shared task"].click()
        app.buttons["Open Disciplina"].click()
        XCTAssertTrue(app.buttons["Reopen Shared task"].waitForExistence(timeout: 3))
    }
    func testDetailsLayoutAndSessionEditing() {
        add("A long task title that must remain readable while its details are open")
        let list = app.outlines["main-task-list"]
        list.staticTexts["A long task title that must remain readable while its details are open"].click()
        let close = app.buttons["Close details"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(list.frame.width, 360)
        let snapshot = XCTAttachment(screenshot: app.windows["main"].screenshot())
        snapshot.name = "readable-task-details"; snapshot.lifetime = .keepAlways; add(snapshot)
        clickDetailButton("Add time…")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        let minutes = sheet.textFields["duration-minutes"]
        minutes.click(); minutes.typeKey("a", modifierFlags: .command); minutes.typeText("2")
        sheet.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Manually added"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["00:02:00"].firstMatch.exists)
        clickDetailButton("Edit duration")
        let editMinutes = app.sheets.firstMatch.textFields["duration-minutes"]
        editMinutes.click(); editMinutes.typeKey("a", modifierFlags: .command); editMinutes.typeText("1")
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["00:02:00"].firstMatch.exists)
        clickDetailButton("Edit duration")
        let savedMinutes = app.sheets.firstMatch.textFields["duration-minutes"]
        savedMinutes.click(); savedMinutes.typeKey("a", modifierFlags: .command); savedMinutes.typeText("1")
        app.sheets.firstMatch.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["00:01:00"].firstMatch.waitForExistence(timeout: 3))
        clickDetailButton("Delete session…")
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Manually added"].exists)
        clickDetailButton("Delete session…")
        app.sheets.firstMatch.buttons["Delete session"].click()
        XCTAssertTrue(app.staticTexts["No work sessions yet."].waitForExistence(timeout: 3))
        clickDetailButton("Close details")
        XCTAssertFalse(close.exists)
        XCTAssertGreaterThan(list.frame.width, 650)
    }

    func testOpeningTimeEditorPausesAndCancelDoesNotResume() {
        add("Pause for editing")
        app.buttons["Start Pause for editing"].click()
        expectMenuBarStatus("Disciplina: Timing Pause for editing")
        app.outlines["main-task-list"].staticTexts["Pause for editing"].click()
        clickDetailButton("Add time…")
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
        app.typeKey(.escape, modifierFlags: [])
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Open Disciplina"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    func testPopoverAboveFullScreenTaskWindow() {
        let window = app.windows["main"]
        let initialHeight = window.frame.height
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Enter Full Screen"].click()
        let fullscreen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.frame.height > initialHeight + 20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fullscreen], timeout: 8), .completed)
        // Native full screen auto-hides the menu bar. Reveal it before targeting
        // the status item, whose accessibility frame is otherwise off-screen.
        // A native navigation toolbar changes the accessible window's top inset.
        // Reveal the menu bar at the display edge, not the content's top edge.
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width * 0.75, dy: 1 - window.frame.minY)).hover()
        let status = app.statusItems.firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        status.click()
        XCTAssertTrue(app.buttons["Open Disciplina"].waitForExistence(timeout: 5))
        app.typeText("Full screen popover capture\n")
        let list = app.descendants(matching: .any)["popover-task-list"].firstMatch
        XCTAssertTrue(list.staticTexts["Full screen popover capture"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "popover-above-full-screen"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.statusItems.firstMatch.click()
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Exit Full Screen"].click()
    }

}

extension DisciplinaUITests {
    /// Drive screen coordinates through TextEdit. Sending events to Disciplina
    /// can activate its main window and mask a Space transition.
    func testStatusItemOverFullScreenTextEdit() throws {
        let id = UUID().uuidString
        let status = app.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Disciplina-\(id).txt")
        try "Full-screen fixture".write(to: fixture, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture) }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "TextEdit", fixture.path]
        try open.run()
        open.waitUntilExit()
        XCTAssertEqual(open.terminationStatus, 0)
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        let window = textEdit.windows.containing(NSPredicate(format: "title CONTAINS %@", id)).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        addTeardownBlock { @MainActor in
            if window.exists {
                window.buttons[XCUIIdentifierCloseWindow].click()
                let discard = window.sheets.buttons["Don't Save"]
                if discard.exists { discard.click() }
            }
        }
        textEdit.menuBars.menuBarItems["View"].click()
        let enter = textEdit.menuItems["Enter Full Screen"]
        if enter.exists { enter.click() } else { textEdit.typeKey(.escape, modifierFlags: []) }
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        XCTAssertEqual(CGGetDisplaysWithPoint(window.frame.centerPoint, 1, &displayID, &displayCount), .success)
        XCTAssertEqual(displayCount, 1)
        let display = CGDisplayBounds(displayID)
        let editorPID = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first?.processIdentifier)
        func fullScreenWindowNumber() -> Int? {
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return entries.first { entry in
                guard entry[kCGWindowOwnerPID as String] as? Int32 == editorPID,
                      entry[kCGWindowLayer as String] as? Int == 0,
                      let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
                return abs(bounds.height - display.height) < 80 && abs(bounds.width - display.width) < 3 && abs(bounds.minX - display.minX) < 3
            }?[kCGWindowNumber as String] as? Int
        }
        func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 8) == .completed
        }
        XCTAssertTrue(waitUntil { fullScreenWindowNumber() != nil })
        let externalID = try XCTUnwrap(fullScreenWindowNumber())
        func clickStatus() {
            let top = window.coordinate(withNormalizedOffset: .zero)
            let reveal = top.withOffset(CGVector(dx: display.minX + display.width * 0.75 - window.frame.minX,
                                                 dy: display.minY + 1 - window.frame.minY))
            reveal.hover()
            // System UI animates independently of the task application's AX tree.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
            XCTAssertTrue(waitUntil { display.contains(status.frame.centerPoint) && status.frame.height > 0 })
            let point = status.frame.centerPoint
            print("Status click at \(point), menu-bar frame \(status.frame)")
            top.withOffset(CGVector(dx: point.x - window.frame.minX, dy: point.y - window.frame.minY)).click()
        }
        let panel = app.dialogs["status-panel"]
        let openButton = panel.buttons["Open Disciplina"]
        clickStatus()
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        XCTAssertEqual(fullScreenWindowNumber(), externalID)
        let title = "Screen work " + id.prefix(6)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, editorPID)
        let panelRect = panel.frame
        XCTAssertTrue(display.contains(panelRect))
        let ordered = try XCTUnwrap(CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                                kCGNullWindowID) as? [[String: Any]])
        let editorIndex = try XCTUnwrap(ordered.firstIndex { $0[kCGWindowNumber as String] as? Int == externalID })
        let appPIDs = NSRunningApplication.runningApplications(withBundleIdentifier: "com.danyloplaksyvy.Disciplina").map(\.processIdentifier)
        XCTAssertTrue(ordered.prefix(editorIndex).contains { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32, appPIDs.contains(pid),
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            return bounds.insetBy(dx: -2, dy: -2).contains(panelRect) && abs(bounds.width - panelRect.width) < 4
        }, "The status panel must be onscreen in front of TextEdit.")
        XCTAssertGreaterThanOrEqual(panel.frame.minY, status.frame.maxY - 2)
        // A nonactivating panel receives keys while TextEdit remains frontmost.
        // Verify the field already owns keyboard focus before injecting any keys.
        let input = panel.textFields["new-task"]
        XCTAssertTrue(waitUntil { input.debugDescription.components(separatedBy: "\n").first?.contains("Keyboard Focused") == true })
        input.typeText(title + "\n")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, editorPID)
        let rows = app.descendants(matching: .any)["popover-task-list"].firstMatch.staticTexts.matching(identifier: title)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(fullScreenWindowNumber(), externalID)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "status-over-full-screen-TextEdit"; screenshot.lifetime = .keepAlways; add(screenshot)
        input.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !openButton.exists })
        clickStatus()
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        XCTAssertEqual(fullScreenWindowNumber(), externalID)
        clickStatus()
        XCTAssertTrue(waitUntil { !openButton.exists })
    }
}

private extension CGRect {
    var centerPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
