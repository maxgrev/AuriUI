import XCTest

@MainActor
final class DemoLiveUITests: XCTestCase {
    func testMarkdownImagesDoNotBypassHostImageResolver() async throws {
        let server = try DemoLiveHTTPFixture(scenario: .markdownImages)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launch(endpoint: endpoint)
        generate(in: app)
        assertLabel(app.staticTexts["demo.live.status"], contains: "Complete")
        XCTAssertTrue(app.staticTexts["Markdown image policy"].exists)

        let imageRequest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.requests.contains { $0.path == "/block-image" || $0.path == "/inline-image" }
        }, object: nil)
        imageRequest.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [imageRequest], timeout: 2), .completed,
                       "Markdown must not fetch images outside the host's resolver")
        XCTAssertEqual(server.requests.map(\.path), ["/screen"])
    }

    func testLiveNetworkNavigationPreservesSelectionsAndDoesNotSendImplicitRequests() async throws {
        let server = try DemoLiveHTTPFixture()
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launch(endpoint: endpoint)
        generate(in: app)
        assertLabel(app.staticTexts["demo.live.status"], contains: "Complete")

        let avocado = app.buttons["auriui.option.avocado"]
        scrollTo(avocado, in: app)
        avocado.tap()
        let review = app.buttons["Review $9.75"]
        scrollTo(review, in: app)
        review.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Ready to send: Lunch: Sourdough, Avocado. Total $9.75.")
        XCTAssertEqual(server.requests.count, 1, "Sending to the host must not generate another screen")

        let next = app.buttons["Next step"]
        scrollTo(next, in: app)
        next.tap()
        let childAction = app.buttons["Send child result"]
        XCTAssertTrue(childAction.waitForExistence(timeout: 10))
        childAction.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "The child screen is complete.")

        let back = app.buttons["BackButton"].exists
            ? app.buttons["BackButton"] : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        scrollTo(review, in: app)
        review.tap()
        assertLabel(app.staticTexts["demo.action"], contains: "Sourdough, Avocado. Total $9.75.")

        let requests = server.requests
        XCTAssertEqual(requests.count, 2, "Returning to a ready screen must reuse its session")
        for request in requests {
            XCTAssertEqual(request.path, "/screen")
            XCTAssertEqual(request.headers["authorization"], "Bearer \(DemoLiveHTTPFixture.token)")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            XCTAssertEqual(body["grounded"] as? Bool, false)
            XCTAssertFalse(String(decoding: request.body, as: UTF8.self).contains(DemoLiveHTTPFixture.token))
        }
        let childBody = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
        XCTAssertEqual(childBody["brief"] as? String, "Lunch: Sourdough, Avocado. Total $9.75.")
    }

    func testLiveHTTPFailureRetriesThroughTheAdapter() async throws {
        let server = try DemoLiveHTTPFixture(scenario: .failureThenSuccess)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launch(endpoint: endpoint)
        generate(in: app)
        assertLabel(app.staticTexts["demo.live.status"], contains: "Could not finish")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "HTTP 503")).firstMatch.exists)
        app.buttons["auriui.retry"].tap()
        assertLabel(app.staticTexts["demo.live.status"], contains: "Complete")
        XCTAssertTrue(app.buttons["Review $8.50"].exists)
        XCTAssertEqual(server.requests.count, 2)
    }

    func testLiveCancellationCanRestartANetworkStream() async throws {
        let server = try DemoLiveHTTPFixture(scenario: .slowThenSuccess)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launch(endpoint: endpoint)
        generate(in: app)
        XCTAssertTrue(app.staticTexts["Build your lunch"].waitForExistence(timeout: 10))
        app.buttons["demo.live.cancel"].tap()
        assertLabel(app.staticTexts["demo.live.status"], contains: "Cancelled")
        XCTAssertEqual(server.requests.count, 1)
        app.buttons["demo.live.restart"].tap()
        assertLabel(app.staticTexts["demo.live.status"], contains: "Complete")
        XCTAssertEqual(server.requests.count, 2)
    }

    func testLiveRejectsAnInvalidAccessToken() async throws {
        let server = try DemoLiveHTTPFixture()
        let endpoint = try await server.start()
        defer { server.stop() }
        let invalidToken = "wrong-demo-access-token-1234567890"
        let app = launch(endpoint: endpoint, token: invalidToken)
        generate(in: app)
        assertLabel(app.staticTexts["demo.live.status"], contains: "Could not finish")
        XCTAssertTrue(app.staticTexts["The backend rejected your authorization. Check your access token."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Review $8.50"].exists)
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(server.requests.first?.headers["authorization"], "Bearer \(invalidToken)")
    }

    func testLeavingALiveStreamDoesNotSendAnotherRequestWhenReturning() async throws {
        let server = try DemoLiveHTTPFixture(scenario: .slowThenSuccess)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launch(endpoint: endpoint)
        generate(in: app)
        XCTAssertTrue(app.staticTexts["Build your lunch"].waitForExistence(timeout: 10))

        app.buttons["Gallery"].tap()
        app.buttons["Live"].tap()
        assertLabel(app.staticTexts["demo.live.status"], contains: "Cancelled")
        XCTAssertEqual(server.requests.count, 1, "Returning to an interrupted stream must not use provider quota")

        app.buttons["demo.live.restart"].tap()
        assertLabel(app.staticTexts["demo.live.status"], contains: "Complete")
        XCTAssertEqual(server.requests.count, 2)
    }

    func testLiveRequiresExplicitSetup() {
        let app = launch()
        generate(in: app)
        assertLabel(app.staticTexts["demo.live.setupError"], contains: "Enter a valid HTTPS Worker URL")
        XCTAssertFalse(app.staticTexts["demo.live.status"].exists)
    }

    private func launch(endpoint: URL? = nil, token: String = DemoLiveHTTPFixture.token) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let endpoint {
            app.launchArguments.append("-AuriUIDemoLiveFixture")
            app.launchEnvironment["AURIUI_DEMO_WORKER_URL"] = endpoint.absoluteString
            app.launchEnvironment["AURIUI_DEMO_ACCESS_TOKEN"] = token
            app.launchEnvironment["AURIUI_DEMO_PROMPT"] = DemoLiveHTTPFixture.prompt
        }
        app.launch()
        let tab = app.buttons["Live"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        return app
    }

    private func generate(in app: XCUIApplication) {
        let generate = app.buttons["demo.live.generate"]
        scrollTo(generate, in: app)
        generate.tap()
    }

    private func assertLabel(_ element: XCUIElement, contains text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        // SwiftUI Form exposes a collection or table on some iOS versions;
        // generated surfaces expose a ScrollView. Check existence before
        // reading a frame so setup works with either accessibility layout.
        let containers = [app.scrollViews.firstMatch, app.collectionViews.firstMatch, app.tables.firstMatch]
        guard let scroll = containers.first(where: \.exists) else {
            XCTAssertTrue(element.exists && element.isHittable, "No scroll container or visible control was found")
            return
        }
        for _ in 0..<8 {
            let navigationBar = app.navigationBars.firstMatch
            let footer = app.staticTexts["Host result"]
            let top = navigationBar.exists ? max(scroll.frame.minY, navigationBar.frame.maxY) : scroll.frame.minY
            let bottom = footer.exists ? min(scroll.frame.maxY, footer.frame.minY - 12) : scroll.frame.maxY
            let viewport = CGRect(x: scroll.frame.minX, y: top, width: scroll.frame.width, height: max(0, bottom - top)).insetBy(dx: 0, dy: 12)
            if element.exists, element.isHittable, viewport.contains(element.frame) { return }
            if element.exists, element.frame.minY < viewport.minY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "The expected control is not visible")
    }
}
