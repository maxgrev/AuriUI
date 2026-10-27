import XCTest

@MainActor
final class AuriUIDemoUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.buttons[title]
        guard tab.waitForExistence(timeout: 5) else {
            XCTFail("Missing \(title) tab")
            return
        }
        guard tab.isHittable else {
            XCTFail("The \(title) tab is not tappable")
            return
        }
        tab.tap()
    }

    private func open(_ sample: String, tab: String, in app: XCUIApplication) {
        selectTab(tab, in: app)
        let link = app.buttons["demo.sample.\(sample)"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let viewport = visibleScrollFrame(scrollView, in: app)
            if isFullyVisible(element, in: viewport) { return }
            if element.exists, element.frame.minY < viewport.minY {
                scrollView.swipeDown()
            } else {
                scrollView.swipeUp()
            }
        }
        XCTAssertTrue(
            isFullyVisible(element, in: visibleScrollFrame(scrollView, in: app)),
            "The control is not fully visible inside the scroll view"
        )
    }

    private func visibleScrollFrame(_ scrollView: XCUIElement, in app: XCUIApplication) -> CGRect {
        let frame = scrollView.frame
        let navigationBar = app.navigationBars.firstMatch
        let footer = app.staticTexts["Host result"]
        let top = navigationBar.exists ? max(frame.minY, navigationBar.frame.maxY) : frame.minY
        let bottom = footer.exists ? min(frame.maxY, footer.frame.minY - 12) : frame.maxY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, bottom - top))
            .insetBy(dx: 0, dy: 12)
    }

    private func isFullyVisible(_ element: XCUIElement, in viewport: CGRect) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return viewport.contains(element.frame)
    }

    private func assertLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 8) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let scrollView = app.scrollViews.firstMatch
        let frame = scrollView.frame
        let navigationBar = app.navigationBars.firstMatch
        let top = navigationBar.exists ? max(frame.minY, navigationBar.frame.maxY) : frame.minY
        // The leading scroll margin sits outside the nested TextEditor, so
        // this drag reaches the outer scroll view's keyboard dismissal.
        let origin = scrollView.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: 4, dy: top - frame.minY + 20))
        let end = origin.withOffset(CGVector(dx: 4, dy: frame.height - 12))
        start.press(forDuration: 0.1, thenDragTo: end)
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    func testSelectionsUpdateExactTotalAndHostAction() {
        let app = launch()
        open("selection", tab: "Interactive", in: app)
        XCTAssertTrue(app.buttons["Review $8.50"].waitForExistence(timeout: 5))
        app.buttons["auriui.option.avocado"].tap()
        app.buttons["auriui.option.bagel"].tap()
        let review = app.buttons["Review $10.25"]
        scrollTo(review, in: app)
        review.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Total $10.25")
        assertLabel(app.staticTexts["demo.action"], contains: "Bagel")
        assertLabel(app.staticTexts["demo.action"], contains: "Avocado")
    }

    func testFormValidatesAndRequiresConfirmation() {
        let app = launch()
        open("form", tab: "Interactive", in: app)
        let submit = app.buttons["auriui.form.demo_search.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
        XCTAssertTrue(app.staticTexts["Error: This field is required."].waitForExistence(timeout: 3))
        assertLabel(app.staticTexts["demo.action"], contains: "No action yet")

        let query = app.textFields["auriui.form.field.query"]
        query.tap()
        query.typeText("native charts\n")
        submit.tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        assertLabel(app.staticTexts["demo.action"], contains: "No action yet")
        confirmation.buttons["Review search"].tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Search for native charts, Any time.")
    }

    func testEveryFormInputReachesHostWithEditedValues() {
        let app = launch()
        open("fields", tab: "Interactive", in: app)
        let activity = app.textFields["auriui.form.field.topic"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        activity.typeText("Reading")

        let notes = app.textViews.firstMatch
        notes.tap()
        notes.typeText("Bring a notebook")
        dismissKeyboard(in: app)

        let time = app.buttons["auriui.form.field.time"]
        scrollTo(time, in: app)
        time.tap()
        app.buttons["Evening"].tap()

        let day = app.datePickers.firstMatch
        scrollTo(day, in: app)
        day.tap()
        let fullDate = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "October 24")).firstMatch
        let calendarDay = fullDate.waitForExistence(timeout: 2) ? fullDate : app.buttons["24"]
        XCTAssertTrue(calendarDay.waitForExistence(timeout: 2))
        calendarDay.tap()
        // Compact date pickers can remain open after choosing a day. Tapping
        // the host navigation title dismisses the calendar without editing it.
        app.navigationBars["Every input type"].staticTexts["Every input type"].tap()

        let duration = app.sliders.firstMatch
        scrollTo(duration, in: app)
        duration.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(duration.value as? String, "120 min")

        let review = app.buttons["auriui.form.all_fields.submit"]
        scrollTo(review, in: app)
        review.tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Review plan"].tap()
        assertLabel(
            app.staticTexts["demo.action"],
            contains: "Plan Reading on 2026-10-24 in the Evening, for 120 min. Notes: Bring a notebook"
        )
    }

    func testHostNavigationKeepsParentSelectionWhenReturning() {
        let app = launch()
        open("selection", tab: "Interactive", in: app)
        let avocado = app.buttons["auriui.option.avocado"]
        XCTAssertTrue(avocado.waitForExistence(timeout: 5))
        avocado.tap()
        let next = app.buttons["Next step"]
        scrollTo(next, in: app)
        next.tap()

        let childAction = app.buttons["Send from this screen"]
        XCTAssertTrue(childAction.waitForExistence(timeout: 5))
        childAction.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Lunch: Sourdough, Avocado. Total $9.75.")

        let backButton = app.buttons["BackButton"].exists
            ? app.buttons["BackButton"]
            : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()
        let parentReview = app.buttons["Review $9.75"]
        XCTAssertTrue(parentReview.waitForExistence(timeout: 5))
        scrollTo(parentReview, in: app)
        parentReview.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Submitted: Lunch: Sourdough, Avocado. Total $9.75.")
    }

    func testRegisteredHostAction() {
        let app = launch()
        open("host", tab: "Interactive", in: app)
        let save = app.buttons["Save favorite"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Favorite saved (1)")
        XCTAssertFalse(app.buttons["Unavailable action"].exists)
    }

    func testInlineDocumentIntegratesWithHostScreen() {
        let app = launch()
        open("inline", tab: "Gallery", in: app)
        XCTAssertTrue(app.staticTexts["A host-owned screen"].waitForExistence(timeout: 5))
        app.buttons["Use embedded action"].tap()
        assertLabel(app.staticTexts["demo.action"], contains: "An action from the embedded document.")
    }

    func testChipAndSourceDeliverTypedHostActions() {
        let app = launch()
        open("inline", tab: "Gallery", in: app)
        let followUp = app.buttons["Try a follow-up"]
        XCTAssertTrue(followUp.waitForExistence(timeout: 5))
        scrollTo(followUp, in: app)
        followUp.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Submitted: An embedded follow-up.")

        let source = app.buttons["Example documentation"]
        scrollTo(source, in: app)
        source.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Open link: https://example.com/docs")
    }

    func testTabsAndExpandableContent() {
        let app = launch()
        open("tabs", tab: "Gallery", in: app)
        let evening = app.buttons["Evening"]
        XCTAssertTrue(evening.waitForExistence(timeout: 5))
        evening.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Evening plan:")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Does this need a server?"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No. This example reads a document")).firstMatch.waitForExistence(timeout: 3))
    }

    func testDetailPageDispatchesToHost() {
        let app = launch()
        open("media", tab: "Gallery", in: app)
        let tile = app.buttons["Hill walk"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.staticTexts["Hill walk details"].waitForExistence(timeout: 3))
        app.buttons["Choose this walk"].tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Choose the fictional Hill walk.")
    }

    func testDetailPageSelectionsAndTotalsStayLocalAndSurviveReopening() throws {
        let app = launch()
        open("media", tab: "Gallery", in: app)

        let rootOrder = app.buttons["Root order $3.00"]
        scrollTo(rootOrder, in: app)
        rootOrder.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Root $3.00: Croutons.")

        let soup = app.buttons["Soup"]
        scrollTo(soup, in: app)
        soup.tap()
        XCTAssertTrue(app.navigationBars["Soup"].waitForExistence(timeout: 3))
        let soupCroutons = try visiblePageOption("croutons", in: app)
        XCTAssertFalse(soupCroutons.isSelected, "A page must not inherit a root option with the same ID")
        soupCroutons.tap()
        XCTAssertTrue(soupCroutons.isSelected)
        let herbs = try visiblePageOption("herbs", in: app)
        herbs.tap()
        let soupTotal = app.buttons["Soup total $7.00"]
        XCTAssertTrue(soupTotal.waitForExistence(timeout: 3))
        soupTotal.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Soup $7.00: Croutons, Herbs.")

        let salad = app.buttons["Salad"]
        scrollTo(salad, in: app)
        salad.tap()
        XCTAssertTrue(app.navigationBars["Salad"].waitForExistence(timeout: 3))
        let saladCroutons = try visiblePageOption("croutons", in: app)
        XCTAssertFalse(saladCroutons.isSelected, "Sibling pages must not share option state")
        saladCroutons.tap()
        let saladTotal = app.buttons["Salad total $8.00"]
        XCTAssertTrue(saladTotal.waitForExistence(timeout: 3))
        saladTotal.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Salad $8.00: Croutons.")

        scrollTo(soup, in: app)
        soup.tap()
        XCTAssertTrue(app.navigationBars["Soup"].waitForExistence(timeout: 3))
        XCTAssertTrue(try visiblePageOption("croutons", in: app).isSelected)
        XCTAssertTrue(try visiblePageOption("herbs", in: app).isSelected)
        XCTAssertTrue(soupTotal.exists, "Reopening a page must retain its own total and selections")
        app.buttons["Done"].tap()

        scrollTo(rootOrder, in: app)
        rootOrder.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Root $3.00: Croutons.")
    }

    private func visiblePageOption(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        let options = app.buttons.matching(identifier: "auriui.option.\(id)")
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 3))
        return try XCTUnwrap(options.allElementsBoundByIndex.first(where: \.isHittable))
    }

    func testChartDataFallback() {
        let app = launch()
        open("data", tab: "Gallery", in: app)
        let data = app.buttons["auri.ui.chart.data.Focus minutes"]
        XCTAssertTrue(data.waitForExistence(timeout: 5))
        scrollTo(data, in: app)
        data.tap()
        let firstRow = app.descendants(matching: .any)["Mon, Focus, 20 min"]
        scrollTo(firstRow, in: app)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["Tue, Focus, 35 min"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Wed, Focus, 30 min"].exists)
    }

    func testCompleteStreamDispatchesAction() {
        let app = launch()
        selectTab("Streaming", in: app)
        app.buttons["demo.stream.success"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Complete · attempt 1")
        let use = app.buttons["Use this result"]
        scrollTo(use, in: app)
        use.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "offline stream completed successfully")
    }

    func testTruncatedStreamPreservesPartialContentAndRetries() {
        let app = launch()
        selectTab("Streaming", in: app)
        app.buttons["demo.stream.truncated"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Needs retry · attempt 1")
        XCTAssertTrue(app.staticTexts["Arriving in sections"].exists)
        XCTAssertTrue(app.staticTexts["This screen is incomplete."].exists)
        app.buttons["auriui.retry"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Complete · attempt 2")
    }

    func testFailedStreamRetries() {
        let app = launch()
        selectTab("Streaming", in: app)
        app.buttons["demo.stream.failure"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Needs retry · attempt 1")
        app.buttons["auriui.retry"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Complete · attempt 2")
    }

    func testCancellingStopsProducerAndCanRestart() {
        let app = launch()
        selectTab("Streaming", in: app)
        app.buttons["demo.stream.slow"].tap()
        XCTAssertTrue(app.staticTexts["Arriving in sections"].waitForExistence(timeout: 5))
        app.buttons["demo.stream.cancel"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Cancelled · producer stopped")
        app.buttons["demo.stream.restart"].tap()
        assertLabel(app.staticTexts["demo.stream.status"], contains: "Complete · attempt 2")
    }
}
