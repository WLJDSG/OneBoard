import Foundation

enum CalendarWeekStart: String, CaseIterable, Identifiable {
    case monday
    case sunday

    var id: String { rawValue }
    var title: String { self == .monday ? "周一" : "周日" }
    var calendarFirstWeekday: Int { self == .monday ? 2 : 1 }
}

struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let day: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool

    var id: Date { date }
}

struct CalendarGrid {
    let calendar: Calendar

    init(calendar: Calendar = .current, weekStart: CalendarWeekStart) {
        var configured = calendar
        configured.firstWeekday = weekStart.calendarFirstWeekday
        configured.minimumDaysInFirstWeek = 4
        self.calendar = configured
    }

    func days(containing displayedMonth: Date, today: Date = Date()) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDay) else { return [] }
        let end = calendar.date(byAdding: .day, value: 42, to: firstWeek.start) ?? lastWeek.end
        var date = firstWeek.start
        var result: [CalendarDay] = []
        while date < end {
            result.append(CalendarDay(
                date: date,
                day: calendar.component(.day, from: date),
                isInDisplayedMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                isToday: calendar.isDate(date, inSameDayAs: today)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    func weekdaySymbols(locale: Locale = .current) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
