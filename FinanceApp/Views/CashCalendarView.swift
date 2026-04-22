import SwiftUI
import SwiftData
import Charts

private struct CalendarQuickAddDraft: Identifiable {
    let id = UUID()
    let date: Date
    let type: TransactionType
}

struct CashCalendarView: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var transactions: [Transaction]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurringTransactions: [RecurringTransaction]
    @Query(filter: #Predicate<Subscription> { $0.isActive == true })
    private var subscriptions: [Subscription]
    @Query private var debts: [Debt]

    @State private var monthOffset = 0
    @State private var selectedDay: CashCalendarDay?
    @State private var quickAddDraft: CalendarQuickAddDraft?

    private let calendar = Calendar.current

    private var displayedMonthStart: Date {
        let todayStart = calendar.startOfDay(for: Date())
        let currentMonth = calendar.dateInterval(of: .month, for: todayStart)?.start ?? todayStart
        return calendar.date(byAdding: .month, value: monthOffset, to: currentMonth) ?? currentMonth
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: displayedMonthStart)
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var monthDays: [CashCalendarDay] {
        CashCalendarAssembler.monthDays(
            referenceDate: displayedMonthStart,
            transactions: transactions,
            categories: categories,
            recurringTransactions: recurringTransactions,
            subscriptions: subscriptions,
            debts: debts
        )
    }

    private var monthDayByDate: [Date: CashCalendarDay] {
        Dictionary(uniqueKeysWithValues: monthDays.map { (calendar.startOfDay(for: $0.date), $0) })
    }

    private var monthGridCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonthStart) else { return [] }
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: monthDays.map { $0.date })

        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var forecast: [CashFlowForecast.DailyForecast] {
        CashFlowForecast.forecast(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            subscriptions: subscriptions
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    calendarCard
                    forecastCard
                }
                .padding(16)
            }
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Cash Calendar"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("calendar.screen")
        .sheet(item: $selectedDay) { day in
            dayDetailsSheet(for: day)
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $quickAddDraft) { draft in
            QuickAddView(prefillType: draft.type, prefillDate: draft.date)
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    monthOffset = max(-1, monthOffset - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(monthOffset <= -1)
                .opacity(monthOffset <= -1 ? 0.35 : 1)
                .accessibilityIdentifier("calendar.month.prev")

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Calendar"))
                        .font(.headline)
                    Text(monthLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(String(localized: "Today")) {
                    monthOffset = 0
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.primaryAccent)

                Button {
                    monthOffset = min(1, monthOffset + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(monthOffset >= 1)
                .opacity(monthOffset >= 1 ? 0.35 : 1)
                .accessibilityIdentifier("calendar.month.next")
            }

            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(monthGridCells.enumerated()), id: \.offset) { _, cellDate in
                    if let cellDate {
                        dayCell(for: cellDate)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clear)
                            .frame(height: 66)
                    }
                }
            }

            Text(String(localized: "Tap a day to open details"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }

    private func dayCell(for date: Date) -> some View {
        let dayDate = calendar.startOfDay(for: date)
        let day = monthDayByDate[dayDate] ?? emptyDay(for: dayDate)
        let today = calendar.isDateInToday(dayDate)
        let actualCount = day.events.filter { $0.status == .actual }.count
        let plannedCount = day.events.filter { $0.status == .planned }.count

        return Button {
            selectedDay = day
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(calendar.component(.day, from: dayDate))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 2)
                    if today {
                        Circle()
                            .fill(AppTheme.primaryAccent)
                            .frame(width: 6, height: 6)
                    }
                }

                if !day.events.isEmpty {
                    Text(signedCompact(day.net))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(day.net >= 0 ? AppTheme.success : AppTheme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: 4) {
                        if actualCount > 0 {
                            Circle()
                                .fill(AppTheme.success)
                                .frame(width: 5, height: 5)
                        }
                        if plannedCount > 0 {
                            Circle()
                                .stroke(AppTheme.warning, lineWidth: 1)
                                .frame(width: 5, height: 5)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(today ? AppTheme.primaryAccent.opacity(0.16) : AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.outline.opacity(0.4), lineWidth: today ? 1.2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.day.\(dayIdString(for: dayDate))")
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Cash Flow Forecast"))
                .font(.headline)

            if let today = forecast.first, let day30 = forecast.last {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Today"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: today.projectedBalance))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "In 30 days"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: day30.projectedBalance))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(day30.projectedBalance >= today.projectedBalance ? AppTheme.success : AppTheme.danger)
                    }
                }
            }

            Chart(forecast) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Balance", NSDecimalNumber(decimal: point.projectedBalance).doubleValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppTheme.primaryAccent)

                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Balance", NSDecimalNumber(decimal: point.projectedBalance).doubleValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppTheme.primaryAccent.opacity(0.12).gradient)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Upcoming Events"))
                    .font(.subheadline.weight(.semibold))

                let eventsWithDates = forecast.filter { !$0.events.isEmpty }
                if eventsWithDates.isEmpty {
                    Text(String(localized: "No scheduled events in the next 30 days"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(eventsWithDates.prefix(10)), id: \.id) { day in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(day.events, id: \.self) { event in
                                Text(event)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }

    private func dayDetailsSheet(for day: CashCalendarDay) -> some View {
        let actualEvents = day.events.filter { $0.status == .actual }
        let plannedEvents = day.events.filter { $0.status == .planned }

        return NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dayTotalsCard(day)
                    eventsSection(
                        title: String(localized: "Actual"),
                        emptyText: String(localized: "No actual events"),
                        events: actualEvents
                    )
                    eventsSection(
                        title: String(localized: "Planned"),
                        emptyText: String(localized: "No planned events"),
                        events: plannedEvents
                    )

                    HStack(spacing: 10) {
                        Button {
                            openQuickAdd(from: day.date, type: .expense)
                        } label: {
                            Text(String(localized: "Add expense"))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.danger)
                        .accessibilityIdentifier("calendar.daySheet.addExpense")

                        Button {
                            openQuickAdd(from: day.date, type: .income)
                        } label: {
                            Text(String(localized: "Add income"))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.success)
                        .accessibilityIdentifier("calendar.daySheet.addIncome")
                    }
                }
                .padding(16)
            }
            .financeNavigationSurface()
            .navigationTitle(dayTitle(for: day.date))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("calendar.daySheet")
        }
    }

    private func dayTotalsCard(_ day: CashCalendarDay) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "Actual"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(CurrencyFormatter.string(from: day.actualIncome - day.actualExpense))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle((day.actualIncome - day.actualExpense) >= 0 ? AppTheme.success : AppTheme.danger)
            }

            HStack {
                Text(String(localized: "Planned"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(CurrencyFormatter.string(from: day.plannedIncome - day.plannedExpense))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle((day.plannedIncome - day.plannedExpense) >= 0 ? AppTheme.success : AppTheme.danger)
            }

            Divider()

            HStack {
                Text(String(localized: "Day Net"))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(CurrencyFormatter.string(from: day.net))
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(day.net >= 0 ? AppTheme.success : AppTheme.danger)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func eventsSection(title: String, emptyText: String, events: [CashCalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if events.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: event.source))
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                            .background(AppTheme.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text(event.title)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 10)

                        Text((event.direction == .income ? "+ " : "− ") + CurrencyFormatter.string(from: event.amount))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(event.direction == .income ? AppTheme.success : AppTheme.danger)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.outline.opacity(0.4), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openQuickAdd(from date: Date, type: TransactionType) {
        selectedDay = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            quickAddDraft = CalendarQuickAddDraft(date: date, type: type)
        }
    }

    private func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, d MMMM")
        return formatter.string(from: date)
    }

    private func emptyDay(for date: Date) -> CashCalendarDay {
        CashCalendarDay(
            date: date,
            events: [],
            actualIncome: .zero,
            actualExpense: .zero,
            plannedIncome: .zero,
            plannedExpense: .zero,
            net: .zero
        )
    }

    private func signedCompact(_ amount: Decimal) -> String {
        if amount == .zero { return "0" }
        let sign = amount > 0 ? "+" : "−"
        return "\(sign)\(NumberAbbreviator.string(from: abs(amount)))"
    }

    private func dayIdString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func symbol(for source: CashCalendarEvent.Source) -> String {
        switch source {
        case .transaction:
            return "list.bullet.rectangle"
        case .recurring:
            return "repeat"
        case .subscription:
            return "arrow.triangle.2.circlepath"
        case .debt:
            return "creditcard"
        }
    }
}
