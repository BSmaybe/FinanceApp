import XCTest

final class FinanceAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_RESET",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        return app
    }

    private func openTransactionsTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
    }

    private func openAnalyticsTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
    }

    private func preferredElement(
        primary: XCUIElement,
        secondary: XCUIElement,
        fallback: XCUIElement,
        identifierTimeout: TimeInterval = 2
    ) -> XCUIElement {
        if primary.waitForExistence(timeout: identifierTimeout) { return primary }
        if secondary.waitForExistence(timeout: 1) { return secondary }
        return fallback
    }

    private func quickAddFab(_ app: XCUIApplication) -> XCUIElement {
        let idButton = app.buttons["transactions.quickAddFab"]
        let idAny = app.descendants(matching: .any)
            .matching(identifier: "transactions.quickAddFab")
            .firstMatch
        return preferredElement(
            primary: idButton,
            secondary: idAny,
            fallback: app.buttons["Quick Add"]
        )
    }

    private func detailedButton(_ app: XCUIApplication) -> XCUIElement {
        let idButton = app.buttons["quickAdd.detailedButton"]
        let idAny = app.descendants(matching: .any)
            .matching(identifier: "quickAdd.detailedButton")
            .firstMatch
        return preferredElement(
            primary: idButton,
            secondary: idAny,
            fallback: app.buttons["Detailed"]
        )
    }

    private func planningCard(
        _ app: XCUIApplication,
        identifier: String,
        fallbackLabel: String
    ) -> XCUIElement {
        let idButton = app.buttons[identifier]
        let idAny = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        return preferredElement(
            primary: idButton,
            secondary: idAny,
            fallback: app.buttons[fallbackLabel]
        )
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        guard element.exists, !element.isHittable else { return }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.isHittable { return }
        }
    }

    private func openQuickAdd(_ app: XCUIApplication) {
        let quickAddFab = quickAddFab(app)
        XCTAssertTrue(quickAddFab.waitForExistence(timeout: 8))
        quickAddFab.tap()

        let detailedButton = detailedButton(app)
        XCTAssertTrue(detailedButton.waitForExistence(timeout: 8))
    }

    func testQuickAddDetailedOpensAddEditScreen() {
        let app = makeApp()
        app.launch()

        openTransactionsTab(app)
        openQuickAdd(app)

        let detailedButton = detailedButton(app)
        XCTAssertTrue(detailedButton.waitForExistence(timeout: 8))
        detailedButton.tap()

        let addEditScreen = app.descendants(matching: .any)
            .matching(identifier: "addEditTransaction.screen")
            .firstMatch
        XCTAssertTrue(addEditScreen.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["addEditTransaction.saveButton"].waitForExistence(timeout: 8))
    }

    func testDashboardBudgetRowOpensQuickAdd() {
        let app = makeApp()
        app.launch()

        let dashboardTab = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 8))
        dashboardTab.tap()

        let budgetRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.budgetRow."))
            .firstMatch
        XCTAssertTrue(budgetRow.waitForExistence(timeout: 8))
        budgetRow.tap()

        let detailedButton = detailedButton(app)
        XCTAssertTrue(detailedButton.waitForExistence(timeout: 8))
    }

    func testCanCreateTransactionFromDetailedForm() {
        let app = makeApp()
        app.launch()

        openTransactionsTab(app)
        openQuickAdd(app)

        let detailedButton = detailedButton(app)
        XCTAssertTrue(detailedButton.waitForExistence(timeout: 8))
        detailedButton.tap()

        let amountField = app.textFields["addEditTransaction.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 8))
        amountField.tap()
        amountField.typeText("123")

        let saveButton = app.buttons["addEditTransaction.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let transactionRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "transactions.row."))
            .firstMatch
        XCTAssertTrue(transactionRow.waitForExistence(timeout: 8))
    }

    func testAnalyticsPlanningOpensWhatIf() {
        let app = makeApp()
        app.launch()

        openAnalyticsTab(app)

        let whatIfCard = planningCard(
            app,
            identifier: "analytics.planning.whatIf",
            fallbackLabel: "What If"
        )
        XCTAssertTrue(whatIfCard.waitForExistence(timeout: 8))
        reveal(whatIfCard, in: app)
        whatIfCard.tap()

        let whatIfScreen = app.descendants(matching: .any)
            .matching(identifier: "whatIf.screen")
            .firstMatch
        XCTAssertTrue(whatIfScreen.waitForExistence(timeout: 8))
    }

    func testAnalyticsPlanningOpensYearlyOverview() {
        let app = makeApp()
        app.launch()

        openAnalyticsTab(app)

        let yearlyOverviewCard = planningCard(
            app,
            identifier: "analytics.planning.yearlyOverview",
            fallbackLabel: "Yearly Overview"
        )
        XCTAssertTrue(yearlyOverviewCard.waitForExistence(timeout: 8))
        reveal(yearlyOverviewCard, in: app)
        yearlyOverviewCard.tap()

        let yearlyOverviewScreen = app.descendants(matching: .any)
            .matching(identifier: "yearlyOverview.screen")
            .firstMatch
        XCTAssertTrue(yearlyOverviewScreen.waitForExistence(timeout: 8))
    }
}
