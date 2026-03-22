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

    private func openAccountsTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
    }

    private func openSettingsTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons.element(boundBy: 4)
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

    func testDashboardBudgetQuickActionOpensBudgetManager() {
        let app = makeApp()
        app.launch()

        let dashboardTab = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 8))
        dashboardTab.tap()

        let budgetAction = app.buttons["dashboard.quickAction.budget"]
        XCTAssertTrue(budgetAction.waitForExistence(timeout: 8))
        budgetAction.tap()

        let budgetManager = app.descendants(matching: .any)
            .matching(identifier: "budgetManager.screen")
            .firstMatch
        XCTAssertTrue(budgetManager.waitForExistence(timeout: 8))
    }

    func testDashboardBudgetManageButtonOpensSetBudget() {
        let app = makeApp()
        app.launch()

        let dashboardTab = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 8))
        dashboardTab.tap()

        let manageBudgetButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.budgetRow.manageBudget."))
            .firstMatch
        XCTAssertTrue(manageBudgetButton.waitForExistence(timeout: 8))
        manageBudgetButton.tap()

        let setBudgetScreen = app.descendants(matching: .any)
            .matching(identifier: "setBudget.screen")
            .firstMatch
        XCTAssertTrue(setBudgetScreen.waitForExistence(timeout: 8))
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

    func testAnalyticsPlanningOpensAnnualOverview() {
        let app = makeApp()
        app.launch()

        openAnalyticsTab(app)

        let annualOverviewCard = planningCard(
            app,
            identifier: "analytics.planning.annualOverview",
            fallbackLabel: "Annual Overview"
        )
        XCTAssertTrue(annualOverviewCard.waitForExistence(timeout: 8))
        reveal(annualOverviewCard, in: app)
        annualOverviewCard.tap()

        let annualOverviewScreen = app.descendants(matching: .any)
            .matching(identifier: "annualOverview.screen")
            .firstMatch
        XCTAssertTrue(annualOverviewScreen.waitForExistence(timeout: 8))
    }

    func testAccountsManageCategoriesOpensCategories() {
        let app = makeApp()
        app.launch()

        openAccountsTab(app)

        let manageCategories = app.buttons["accounts.manageCategories"]
        XCTAssertTrue(manageCategories.waitForExistence(timeout: 8))
        manageCategories.tap()

        let categoriesScreen = app.descendants(matching: .any)
            .matching(identifier: "categories.screen")
            .firstMatch
        XCTAssertTrue(categoriesScreen.waitForExistence(timeout: 8))
    }

    func testDashboardRecentActivityCTAOpensTransactionsTab() {
        let app = makeApp()
        app.launch()

        let dashboardTab = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 8))
        dashboardTab.tap()

        let openTransactions = app.buttons["dashboard.recentActivity.openTransactions"]
        XCTAssertTrue(openTransactions.waitForExistence(timeout: 8))
        reveal(openTransactions, in: app)
        openTransactions.tap()

        let transactionsList = app.descendants(matching: .any)
            .matching(identifier: "transactions.list")
            .firstMatch
        let emptyState = app.descendants(matching: .any)
            .matching(identifier: "transactions.emptyState")
            .firstMatch
        XCTAssertTrue(transactionsList.waitForExistence(timeout: 8) || emptyState.waitForExistence(timeout: 8))
    }

    func testSettingsShowsSystemSectionsOnly() {
        let app = makeApp()
        app.launch()

        openSettingsTab(app)

        let settingsScreen = app.descendants(matching: .any)
            .matching(identifier: "settings.screen")
            .firstMatch
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Personalization"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Planning Rules"].exists)
        XCTAssertTrue(app.staticTexts["Notifications & Live Activity"].exists)

        XCTAssertFalse(app.staticTexts["Categories"].exists)
        XCTAssertFalse(app.staticTexts["Subscriptions"].exists)
        XCTAssertFalse(app.staticTexts["Debts"].exists)
    }

    func testDashboardShowsCoreSections() {
        let app = makeApp()
        app.launch()

        let dashboardTab = app.tabBars.buttons.element(boundBy: 0)
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 8))
        dashboardTab.tap()

        let heroSection = app.descendants(matching: .any)
            .matching(identifier: "dashboard.hero.section")
            .firstMatch
        XCTAssertTrue(heroSection.waitForExistence(timeout: 8))

        let actionsSection = app.descendants(matching: .any)
            .matching(identifier: "dashboard.primaryActions.section")
            .firstMatch
        XCTAssertTrue(actionsSection.waitForExistence(timeout: 8))

        let monthSection = app.descendants(matching: .any)
            .matching(identifier: "dashboard.thisMonth.section")
            .firstMatch
        XCTAssertTrue(monthSection.waitForExistence(timeout: 8))
        reveal(monthSection, in: app)

        let commitmentsSection = app.descendants(matching: .any)
            .matching(identifier: "dashboard.commitments.section")
            .firstMatch
        XCTAssertTrue(commitmentsSection.waitForExistence(timeout: 8))

        let recentSection = app.descendants(matching: .any)
            .matching(identifier: "dashboard.recentActivity.section")
            .firstMatch
        XCTAssertTrue(recentSection.waitForExistence(timeout: 8))
    }
}
