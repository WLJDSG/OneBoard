import SwiftUI
import LunarSwift

struct ChineseCalendarInfo {
    let lunar: String
    let festival: String?
    let term: String?
    let work: Bool?
    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let solar = Solar(year: c.year!, month: c.month!, day: c.day!)
        let value = solar.lunar
        lunar = value.day == 1 ? value.monthInChinese + "月" : value.dayInChinese
        term = value.jieQi.isEmpty ? nil : value.jieQi
        let holiday = HolidayUtil.getHolidayByYmd(year: c.year!, month: c.month!, day: c.day!)
        work = holiday?.work
        festival = holiday?.work == false ? holiday?.name : (solar.festivals + value.festivals).first
    }
}

struct CalendarPanelView: View {
    @AppStorage(Constants.UserDefaultsKeys.calendarWeekStart) private var weekStartRaw = CalendarWeekStart.monday.rawValue
    @AppStorage("calendar.countdowns") private var countdownData = Data()
    @State private var month = Date()
    @State private var selected = Date()
    @State private var tab = 0
    @State private var filter = "全部"
    @ObservedObject private var card = CalendarPanelWindowManager.shared.card
    @State private var adding = false
    @State private var title = ""
    @State private var newDate = Date()
    @ObservedObject private var todos = TodoListViewModel.shared
    private var grid: CalendarGrid { CalendarGrid(weekStart: CalendarWeekStart(rawValue: weekStartRaw) ?? .monday) }
    private var days: [CalendarDay] { grid.days(containing: month) }
    private var countdowns: [CalendarCountdown] { (try? JSONDecoder().decode([CalendarCountdown].self, from: countdownData)) ?? [] }
    private let blue = Color(red: 0.04, green: 0.49, blue: 0.98)

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    HStack(spacing: 14) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        Text(month, format: .dateTime.year().month(.twoDigits)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        Button { move(1) } label: { Image(systemName: "chevron.right") }
                    }.buttonStyle(.plain).padding(11).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    Button { month = Date(); selected = Date() } label: { Label("今天", systemImage: "calendar.badge.clock") }.buttonStyle(.bordered)
                    Spacer(minLength: 0)
                    CalendarClock().font(.system(size: 12, weight: .medium))
                }.frame(height: 44)
                HStack {
                    Text("周").frame(width: 22)
                    ForEach(Array(grid.weekdaySymbols(locale: Locale(identifier: "zh_CN")).enumerated()), id: \.offset) { _, value in
                        Text(value).frame(maxWidth: .infinity)
                    }
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(height: 24)
                Divider()
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { row in
                            HStack(spacing: 3) {
                                Text("\(grid.calendar.component(.weekOfYear, from: days[row * 7].date))")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 22)
                                ForEach(Array(days[(row * 7)..<(row * 7 + 7)])) { day in
                                    dayCell(day).frame(maxWidth: .infinity)
                                }
                            }.frame(height: geometry.size.height / 6)
                        }
                    }
                }
                HStack {
                    Text(selected, format: .dateTime.year().month().day().weekday())
                    Text(CalendarLunar.label(selected))
                    Spacer()
                    if Calendar.current.component(.year, from: month) > 2026 { Text("该年调休安排尚未发布").foregroundStyle(.orange) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 530, maxWidth: .infinity)
            Divider().padding(.vertical, 16)
            sidebar.frame(width: 300).padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $adding) {
            VStack(spacing: 16) {
                Text(tab == 0 ? "添加倒数日" : "添加待办").font(.headline)
                TextField("名称", text: $title)
                if tab == 0 { DatePicker("日期", selection: $newDate, displayedComponents: .date) }
                HStack {
                    Button("取消") { adding = false }
                    Button("添加") {
                        if tab == 0 { save(countdowns + [CalendarCountdown(title: title, date: newDate)]) }
                        else { todos.addTodo(text: title) }
                        title = ""; adding = false
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 340)
        }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let info = ChineseCalendarInfo(date: day.date)
        let active = Calendar.current.isDate(selected, inSameDayAs: day.date)
        return Button {
            selected = day.date
            if !day.isInDisplayedMonth { month = day.date }
        } label: {
            VStack(spacing: 5) {
                Text("\(day.day)").font(.system(size: 25, weight: day.isInDisplayedMonth ? .semibold : .regular))
                    .overlay(alignment: .topTrailing) {
                        if let work = info.work {
                            Text(work ? "班" : "休").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .padding(3).background(work ? Color.orange : Color.green, in: Circle()).offset(x: 14, y: -5)
                        }
                    }
                Text(info.festival ?? info.term ?? info.lunar)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(info.festival != nil ? Color(red: 0.72, green: 0.29, blue: 0.22) : info.term != nil ? blue : .secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(info.festival != nil ? Color.orange.opacity(0.07) : info.term != nil ? blue.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 5))
            }
            .foregroundStyle(day.isToday ? blue : day.isInDisplayedMonth ? .primary : .secondary)
            .frame(maxWidth: .infinity).frame(height: 62)
            .background {
                if active { RoundedRectangle(cornerRadius: 12).fill(blue.opacity(day.isToday ? 0.22 : 0.14)) }
                else if day.isToday { Circle().fill(blue.opacity(0.1)).frame(width: 62, height: 62) }
            }
            .overlay {
                if active { RoundedRectangle(cornerRadius: 12).stroke(blue, lineWidth: 2) }
                else if day.isToday { Circle().stroke(blue.opacity(0.4)).frame(width: 62, height: 62) }
            }
        }.buttonStyle(.plain)
    }

    private var sidebar: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<2) { index in
                        Button { tab = index } label: {
                            Label(index == 0 ? "倒数日" : "待办", systemImage: index == 0 ? "hourglass" : "checklist")
                                .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(tab == index ? blue : .secondary)
                                .background(tab == index ? blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.padding(3).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                Spacer(minLength: 0)
                Button { card.setPinned(!card.pinned) } label: {
                    Image(systemName: card.pinned ? "pin.fill" : "pin").foregroundStyle(card.pinned ? blue : .secondary)
                        .frame(width: 34, height: 34).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help(card.pinned ? "取消置顶" : "置顶")
            }.frame(height: 44)
            if tab == 0 {
                HStack {
                    ForEach(["全部", "节假日", "24 节气", "自定义"], id: \.self) { item in
                        Button { filter = item } label: {
                            VStack(spacing: 0) {
                                Text(item).font(.system(size: 11, weight: .semibold)).foregroundStyle(filter == item ? blue : .secondary)
                            }
                        }.buttonStyle(.plain).frame(maxWidth: .infinity)
                    }
                }.frame(height: 24)
            } else {
                Color.clear.frame(height: 24)
            }
            Divider()
            Button { adding = true } label: {
                Label(tab == 0 ? "添加倒数日" : "添加待办", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.buttonStyle(.plain).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            ScrollView {
                LazyVStack(spacing: 10) {
                    if tab == 0 {
                        ForEach(events) { event in
                            HStack {
                                Image(systemName: event.kind == "24 节气" ? "leaf.fill" : "calendar")
                                    .foregroundStyle(event.kind == "24 节气" ? blue : .green).frame(width: 34, height: 36)
                                    .background(blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title).font(.system(size: 13, weight: .semibold))
                                    Text(event.date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let remaining = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: event.date).day ?? 0
                                Text(remaining == 0 ? "今天" : "\(abs(remaining)) 天\(remaining < 0 ? "前" : "后")").foregroundStyle(blue).font(.system(size: 13, weight: .medium))
                            }.padding(10).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.06)))
                            .contextMenu { if let id = event.customID { Button("删除", role: .destructive) { save(countdowns.filter { $0.id != id }) } } }
                        }
                        if events.isEmpty { Text("暂无倒数日").foregroundStyle(.secondary).padding() }
                    } else {
                        ForEach(todos.activeItems) { item in
                            HStack {
                                Button { todos.toggleComplete(item) } label: { Image(systemName: "circle") }.buttonStyle(.plain)
                                Text(item.text).lineLimit(3); Spacer()
                            }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }
    private struct Event: Identifiable {
        let title: String; let date: Date; let kind: String; var customID: UUID? = nil
        var id: String { customID?.uuidString ?? "\(date.timeIntervalSince1970)-\(kind)-\(title)" }
    }
    private var events: [Event] {
        var result = countdowns.map { Event(title: $0.title, date: Calendar.current.startOfDay(for: $0.date), kind: "自定义", customID: $0.id) }
        var previousHoliday: String?
        let today = Calendar.current.startOfDay(for: Date())
        for offset in 0..<65 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: today)!
            let info = ChineseCalendarInfo(date: date)
            if let term = info.term { result.append(Event(title: term, date: date, kind: "24 节气")) }
            if let festival = info.festival, festival != previousHoliday {
                result.append(Event(title: festival, date: date, kind: "节假日"))
            }
            previousHoliday = info.festival
        }
        return result.filter { filter == "全部" || $0.kind == filter }.sorted { $0.date < $1.date }
    }
    private func move(_ offset: Int) {
        let first = Calendar.current.dateInterval(of: .month, for: month)!.start
        month = Calendar.current.date(byAdding: .month, value: offset, to: first)!
    }
    private func save(_ items: [CalendarCountdown]) { countdownData = (try? JSONEncoder().encode(items)) ?? Data() }
}

private struct CalendarClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 3) {
                Text(context.date, format: .dateTime.hour().minute().second()).monospacedDigit()
                Text(context.date, format: .dateTime.month().day().weekday()).foregroundStyle(.secondary)
            }
        }
    }
}

struct CalendarSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.calendarWeekStart) private var weekStartRaw = CalendarWeekStart.monday.rawValue
    @AppStorage(Constants.UserDefaultsKeys.calendarShowInMenuBar) private var showInMenuBar = true

    var body: some View {
        SettingsForm {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("每周开始于").font(.system(size: 13, weight: .semibold))
                        Text("选择月历的每周第一天").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("每周开始于", selection: $weekStartRaw) {
                        ForEach(CalendarWeekStart.allCases) { Text($0.title).tag($0.rawValue) }
                    }.labelsHidden().frame(width: 150)
                }
            } header: { Text("日历显示") }

            Section {
                Toggle(isOn: $showInMenuBar) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("在菜单栏菜单显示日历").font(.system(size: 13, weight: .semibold))
                        Text("开启后可从 OneBoard 菜单快速打开月历").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("菜单栏日历") }

        }
        .onChange(of: showInMenuBar) { _, _ in MenuBarManager.shared.updateCalendarStatusItemVisibility() }
    }
}

struct CalendarCountdown: Codable, Identifiable {
    var id = UUID()
    let title: String
    let date: Date
}

enum CalendarLunar {
    static func label(_ date: Date) -> String {
        let components = Calendar(identifier: .chinese).dateComponents([.month, .day, .isLeapMonth], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        if components.isLeapMonth != true {
            if month == 1 && day == 1 { return "春节" }
            if month == 1 && day == 15 { return "元宵节" }
            if month == 5 && day == 5 { return "端午节" }
            if month == 8 && day == 15 { return "中秋节" }
        }
        if day == 1 {
            let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
            return (components.isLeapMonth == true ? "闰" : "") + months[max(0, min(11, month - 1))] + "月"
        }
        let numbers = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if day <= 10 { return "初" + numbers[day - 1] }
        if day < 20 { return "十" + numbers[day - 11] }
        if day == 20 { return "二十" }
        if day < 30 { return "廿" + numbers[day - 21] }
        return "三十"
    }
}
