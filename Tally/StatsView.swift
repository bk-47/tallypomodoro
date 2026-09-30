import SwiftUI
import AppKit

struct StatsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case week, totals, log
        var id: String { rawValue }
    }

    enum Dropdown { case filter, export }

    @ObservedObject private var store = LogStore.shared
    @State private var tab: Tab = .week
    @State private var weekOffset = 0
    /// Lower-cased label being shown, or nil for all work.
    @State private var filter: String?
    @State private var open: Dropdown?
    @State private var search = ""
    @State private var renaming: RenameTarget?

    private var cal: Calendar { Fmt.calendar }

    private var week: DateInterval {
        let ref = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return cal.dateInterval(of: .weekOfYear, for: ref) ?? DateInterval(start: ref, duration: 7 * 86400)
    }

    private var weekTitle: String {
        "\(Fmt.dayMonth.string(from: week.start)) – \(Fmt.dayMonth.string(from: week.end.addingTimeInterval(-1)))"
    }

    private func matches(_ e: LogEntry) -> Bool {
        guard let filter else { return true }
        return e.phase == .work && e.label.lowercased() == filter
    }

    var body: some View {
        let all = store.entries(in: week)
        let shown = all.filter(matches)
        ClassicWindow(title: "tally stats", id: "stats") {
            VStack(spacing: 0) {
                toolbar(all)
                    .zIndex(2)
                Rule()
                Group {
                    switch tab {
                    case .week:
                        WeekTimeline(week: week, entries: shown, onRename: { renaming = $0 })
                    case .totals:
                        if let filter {
                            LabelTotals(
                                label: filter,
                                week: week,
                                entries: shown,
                                allTime: store.entries.filter(matches),
                                onExport: { open = .export },
                                onRename: { renaming = .label(filter) }
                            )
                        } else {
                            TotalsView(week: week, entries: shown)
                        }
                    case .log:
                        LogList(entries: Array(shown.reversed()), onRename: { renaming = $0 })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if open != nil {
                        Color.white.opacity(0.001).onTapGesture { open = nil }
                    }
                }
            }
        }
        .overlay {
            if let target = renaming {
                ZStack {
                    Color.white.opacity(0.001).onTapGesture { renaming = nil }
                    RenameDialog(
                        target: target,
                        count: target.count(in: store.entries),
                        onCancel: { renaming = nil },
                        onSave: { apply(target, $0) }
                    )
                }
            }
        }
        .frame(minWidth: 960, minHeight: 560)
        .background(WindowAccessor())
    }

    private func apply(_ target: RenameTarget, _ newLabel: String) {
        let new = newLabel.trimmed.lowercased()
        renaming = nil
        switch target {
        case .block(let e):
            store.rename(e.id, to: new)
        case .label(let old):
            store.renameAll(from: old, to: new)
            if filter == old.lowercased() { filter = new.isEmpty ? nil : new }
        }
    }

    // MARK: Toolbar

    private func toolbar(_ all: [LogEntry]) -> some View {
        HStack(spacing: 16) {
            tabs
            Spacer()
            HStack(spacing: 12) {
                Button("<") { weekOffset -= 1 }
                    .buttonStyle(BoxButtonStyle())
                    .help("previous week")
                Text(weekTitle)
                Button(">") { weekOffset += 1 }
                    .buttonStyle(BoxButtonStyle())
                    .disabled(weekOffset >= 0)
                    .opacity(weekOffset >= 0 ? 0.3 : 1)
                    .help("next week")
                Button("this week") { weekOffset = 0 }
                    .buttonStyle(LinkButtonStyle())
                    .disabled(weekOffset == 0)
                    .opacity(weekOffset == 0 ? 0.3 : 1)
            }
            Spacer()
            filterPopup(all)
            exportPopup
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                let selected = tab == t
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .foregroundStyle(selected ? Theme.paper : Theme.ink)
                        .background(selected ? Theme.ink : Theme.paper)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    if t != .week { Rectangle().fill(Theme.ink).frame(width: 1) }
                }
            }
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
    }

    private func popupFrame<L: View>(active: Bool, @ViewBuilder label: () -> L) -> some View {
        label()
            .foregroundStyle(active ? Theme.paper : Theme.ink)
            .background(active ? Theme.ink : Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            .background(Rectangle().fill(Theme.ink).offset(x: 1, y: 1))
    }

    private func filterPopup(_ all: [LogEntry]) -> some View {
        let active = open == .filter
        return popupFrame(active: active) {
            HStack(spacing: 0) {
                Button {
                    search = ""
                    open = active ? nil : .filter
                } label: {
                    HStack {
                        Text(filter ?? "all work").lineLimit(1).truncationMode(.tail)
                        Spacer()
                        DownArrow()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 210)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if filter != nil {
                    Button { filter = nil } label: {
                        Text("×")
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .leading) { Rectangle().fill(active ? Theme.paper : Theme.ink).frame(width: 1) }
                    .help("show all work")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if active {
                filterMenu(all)
                    .frame(width: 300)
                    .offset(y: 30)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private func filterMenu(_ all: [LogEntry]) -> some View {
        var weekMinutes: [String: Int] = [:]
        for e in all where e.phase == .work {
            weekMinutes[e.label.lowercased(), default: 0] += e.seconds
        }
        let q = search.trimmed.lowercased()
        let labels = store.allLabels.filter { q.isEmpty || $0.lowercased().contains(q) }
        return MenuPanel {
            TextField("", text: $search, prompt: Text("find…"))
                .textFieldStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 6)
            MenuRow(title: "all work", checked: filter == nil) {
                filter = nil
                open = nil
            }
            MenuDivider()
            MenuInfo(text: "recent first, this week's time")
                .font(Theme.font(11))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(labels, id: \.self) { l in
                        let key = l.lowercased()
                        MenuRow(
                            title: l,
                            detail: weekMinutes[key].map { ($0 / 60).hoursMinutes } ?? "–",
                            checked: filter == key
                        ) {
                            filter = key
                            open = nil
                        }
                    }
                }
            }
            .frame(height: min(330, CGFloat(max(labels.count, 1)) * 22))
        }
    }

    private var exportPopup: some View {
        let active = open == .export
        return popupFrame(active: active) {
            Button { open = active ? nil : .export } label: {
                HStack(spacing: 10) {
                    Text("export")
                    DownArrow()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .topTrailing) {
            if active {
                MenuPanel {
                    Group {
                        if let filter { MenuInfo(text: "only \(filter)") }
                        MenuInfo(text: "week shown")
                        MenuRow(title: "csv") { export(week, "tally \(weekTitle)", .csv) }
                        MenuRow(title: "excel") { export(week, "tally \(weekTitle)", .xlsx) }
                        MenuDivider()
                    }
                    Group {
                        MenuInfo(text: "this month")
                        MenuRow(title: "csv") { exportMonth(.csv) }
                        MenuRow(title: "excel") { exportMonth(.xlsx) }
                        MenuDivider()
                    }
                    Group {
                        MenuInfo(text: "everything")
                        MenuRow(title: "csv") { export(nil, "tally log", .csv) }
                        MenuRow(title: "excel") { export(nil, "tally log", .xlsx) }
                    }
                }
                .frame(width: 220)
                .offset(y: 30)
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private func export(_ interval: DateInterval?, _ name: String, _ format: ExportFormat) {
        open = nil
        var list = interval.map { store.entries(in: $0) } ?? store.entries
        var fileName = name
        if let filter {
            list = list.filter(matches)
            fileName = "tally \(filter) " + name.replacingOccurrences(of: "tally ", with: "")
        }
        Exporter.run(list, format: format, name: fileName)
    }

    private func exportMonth(_ format: ExportFormat) {
        guard let month = cal.dateInterval(of: .month, for: Date()) else { return }
        export(month, "tally \(Fmt.monthYear.string(from: Date()).lowercased())", format)
    }
}

// MARK: - Week timeline

struct WeekTimeline: View {
    let week: DateInterval
    let entries: [LogEntry]
    var onRename: (RenameTarget) -> Void = { _ in }

    private let cal = Fmt.calendar
    private let dayColumn: CGFloat = 54
    private let rowHeight: CGFloat = 70

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// 8am to 6pm, widened to fit whatever was logged.
    private var span: HourSpan {
        var lo = 8, hi = 18
        for e in entries {
            lo = min(lo, cal.component(.hour, from: e.start))
            if cal.isDate(e.end, inSameDayAs: e.start) {
                let endHour = cal.component(.hour, from: e.end) + (cal.component(.minute, from: e.end) > 0 ? 1 : 0)
                hi = max(hi, endHour)
            } else {
                hi = 24
            }
        }
        return HourSpan(lo: lo, hi: min(24, max(hi, lo + 1)))
    }

    var body: some View {
        GeometryReader { geo in
            let s = span
            let width = max(300, geo.size.width - dayColumn - 48)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ForEach(s.lo...s.hi, id: \.self) { h in
                            Text(hourLabel(h))
                                .font(Theme.font(11))
                                .fixedSize()
                                .offset(x: s.x(hour: h, width: width) - 10)
                        }
                    }
                    .frame(width: width, height: 20, alignment: .topLeading)
                    .padding(.leading, dayColumn)
                    ForEach(days, id: \.self) { day in
                        DayRow(
                            day: day,
                            entries: entries.filter { cal.isDate($0.start, inSameDayAs: day) },
                            span: s,
                            width: width,
                            height: rowHeight,
                            labelWidth: dayColumn,
                            onRename: onRename
                        )
                    }
                    DottedRule()
                    legend
                        .padding(.leading, dayColumn)
                        .padding(.top, 10)
                    if entries.isEmpty {
                        Text("nothing logged this week.")
                            .padding(.leading, dayColumn)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 24) {
            HStack(spacing: 6) {
                Rectangle().fill(Theme.ink).frame(width: 18, height: 10)
                Text("work")
            }
            HStack(spacing: 6) {
                Rectangle().strokeBorder(Theme.ink, lineWidth: 1).frame(width: 18, height: 10)
                Text("stopped early")
            }
            HStack(spacing: 6) {
                Rectangle().fill(Theme.dither)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    .frame(width: 18, height: 10)
                Text("break")
            }
        }
        .font(Theme.font(11))
    }

    private func hourLabel(_ h: Int) -> String {
        switch h {
        case 0, 24: return "12am"
        case 12: return "12pm"
        case 1..<12: return "\(h)am"
        default: return "\(h - 12)pm"
        }
    }
}

struct HourSpan {
    let lo: Int
    let hi: Int
    func x(hour: Int, width: CGFloat) -> CGFloat {
        CGFloat(hour - lo) / CGFloat(max(1, hi - lo)) * width
    }
}

private struct DayRow: View {
    let day: Date
    let entries: [LogEntry]
    let span: HourSpan
    let width: CGFloat
    let height: CGFloat
    let labelWidth: CGFloat
    let onRename: (RenameTarget) -> Void

    private let cal = Fmt.calendar

    private struct Run: Identifiable {
        let id: UUID
        let label: String
        let start: Date
        var end: Date
        var seconds: Int
    }

    /// Consecutive work blocks with the same label, allowing for the breaks in between.
    private var runs: [Run] {
        var out: [Run] = []
        for e in entries.filter({ $0.phase == .work }).sorted(by: { $0.start < $1.start }) {
            if var last = out.last,
               last.label.lowercased() == e.displayLabel.lowercased(),
               e.start.timeIntervalSince(last.end) <= 25 * 60 {
                last.end = e.end
                last.seconds += e.seconds
                out[out.count - 1] = last
            } else {
                out.append(Run(id: e.id, label: e.displayLabel, start: e.start, end: e.end, seconds: e.seconds))
            }
        }
        return out
    }

    private func x(_ d: Date) -> CGFloat {
        let origin = cal.startOfDay(for: day).addingTimeInterval(TimeInterval(span.lo * 3600))
        let total = TimeInterval(max(1, span.hi - span.lo) * 3600)
        return CGFloat(min(max(d.timeIntervalSince(origin) / total, 0), 1)) * width
    }

    var body: some View {
        let today = cal.isDateInToday(day)
        VStack(spacing: 0) {
            DottedRule()
            HStack(alignment: .top, spacing: 0) {
                Text(Fmt.dayName.string(from: day))
                    .font(Theme.font(13, bold: today))
                    .frame(width: labelWidth, alignment: .leading)
                    .padding(.top, 10)
                ZStack(alignment: .topLeading) {
                    ForEach(entries) { e in block(e) }
                    ForEach(runs) { r in runLabel(r) }
                }
                .frame(width: width, height: height - 1, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func block(_ e: LogEntry) -> some View {
        let x0 = x(e.start)
        let w = max(3, x(e.end) - x0 - 2)
        if e.phase == .work {
            let minutes = Text("\(Int(e.minutes.rounded()))").font(Theme.font(11))
            Group {
                if e.completed {
                    Rectangle().fill(Theme.ink)
                        .overlay { if w > 22 { minutes.foregroundStyle(Theme.paper) } }
                } else {
                    Rectangle().fill(Theme.paper)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                        .overlay { if w > 22 { minutes } }
                }
            }
            .frame(width: w, height: 18)
            .contentShape(Rectangle())
            .contextMenu { RenameMenu(entry: e, onRename: onRename) }
            .offset(x: x0, y: 10)
            .help("\(e.displayLabel)\n\(Fmt.clock.string(from: e.start))–\(Fmt.clock.string(from: e.end)), \(Int(e.minutes.rounded())) min. right-click to rename.")
        } else {
            Rectangle().fill(Theme.dither)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                .frame(width: max(4, w), height: 10)
                .offset(x: x0, y: 14)
                .help("\(e.phase.title)\n\(Fmt.clock.string(from: e.start))–\(Fmt.clock.string(from: e.end))")
        }
    }

    @ViewBuilder
    private func runLabel(_ r: Run) -> some View {
        let x0 = x(r.start)
        let w = max(24, x(r.end) - x0 - 2)
        VStack(alignment: .leading, spacing: 3) {
            Bracket()
                .stroke(Theme.ink, lineWidth: 1)
                .frame(width: w, height: 5)
            Text("\(r.label)  \((r.seconds / 60).hoursMinutes)")
                .font(Theme.font(11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: w, alignment: .leading)
        }
        .offset(x: x0, y: 32)
    }
}

// MARK: - Totals (all work)

struct TotalsView: View {
    let week: DateInterval
    let entries: [LogEntry]

    private let cal = Fmt.calendar

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    private var work: [LogEntry] { entries.filter { $0.phase == .work } }

    var body: some View {
        ScrollView {
            if work.isEmpty {
                Text("nothing logged this week.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            } else {
                HStack(alignment: .top, spacing: 48) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(days, id: \.self) { day in
                            let list = work.filter { cal.isDate($0.start, inSameDayAs: day) }
                            if !list.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    LeaderRow(
                                        title: Fmt.dayShort.string(from: day),
                                        middle: "\(list.filter(\.completed).count) done",
                                        value: (list.reduce(0) { $0 + $1.seconds } / 60).hoursMinutes,
                                        bold: true
                                    )
                                    ForEach(LabelLine.lines(list)) { line in
                                        LeaderRow(title: line.label, middle: "\(line.count)", value: (line.seconds / 60).hoursMinutes)
                                            .font(Theme.font(11))
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        LeaderRow(
                            title: "week",
                            middle: "\(work.filter(\.completed).count) done",
                            value: (work.reduce(0) { $0 + $1.seconds } / 60).hoursMinutes,
                            bold: true
                        )
                        DottedRule().padding(.vertical, 4)
                        ForEach(LabelLine.lines(work)) { line in
                            LeaderRow(title: line.label, middle: "\(line.count)", value: (line.seconds / 60).hoursMinutes)
                                .font(Theme.font(11))
                        }
                    }
                    .padding(18)
                    .frame(width: 320, alignment: .leading)
                    .background(Theme.paper)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    .background(Rectangle().fill(Theme.ink).offset(x: 2, y: 2))
                }
                .padding(24)
            }
        }
    }
}

struct LabelLine: Identifiable {
    let id: String
    let label: String
    let count: Int
    let seconds: Int

    static func lines(_ list: [LogEntry]) -> [LabelLine] {
        var map: [String: (label: String, count: Int, secs: Int)] = [:]
        for e in list where e.phase == .work {
            let key = e.displayLabel.lowercased()
            var v: (label: String, count: Int, secs: Int) = map[key] ?? (e.displayLabel, 0, 0)
            if e.completed { v.count += 1 }
            v.secs += e.seconds
            map[key] = v
        }
        return map
            .map { LabelLine(id: $0.key, label: $0.value.label, count: $0.value.count, seconds: $0.value.secs) }
            .sorted { $0.seconds > $1.seconds }
    }
}

/// "title ........ middle   value"
struct LeaderRow: View {
    let title: String
    var middle: String = ""
    let value: String
    var bold = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(title)
                .fontWeight(bold ? .bold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            DottedRule()
                .padding(.bottom, 4)
                .frame(minWidth: 12)
            if !middle.isEmpty { Text(middle) }
            Text(value).frame(minWidth: 60, alignment: .trailing)
        }
    }
}

// MARK: - Totals (one label)

struct LabelTotals: View {
    let label: String
    let week: DateInterval
    let entries: [LogEntry]
    let allTime: [LogEntry]
    let onExport: () -> Void
    let onRename: () -> Void

    private let cal = Fmt.calendar

    private var activeDays: [Date] {
        (0..<7)
            .compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
            .filter { day in entries.contains { cal.isDate($0.start, inSameDayAs: day) } }
    }

    var body: some View {
        let weekSecs = entries.reduce(0) { $0 + $1.seconds }
        let done = entries.filter(\.completed).count
        let dayCount = Set(entries.map { cal.startOfDay(for: $0.start) }).count
        let allSecs = allTime.reduce(0) { $0 + $1.seconds }
        let first = allTime.map(\.start).min()

        ScrollView {
            HStack(alignment: .top, spacing: 48) {
                if entries.isEmpty {
                    Text("nothing logged for this label this week.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 40, alignment: .top), GridItem(.flexible(), alignment: .top)],
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(activeDays, id: \.self) { day in
                            let list = entries.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
                            VStack(alignment: .leading, spacing: 3) {
                                    LeaderRow(
                                        title: Fmt.dayShort.string(from: day),
                                        middle: "\(list.filter(\.completed).count) done",
                                        value: (list.reduce(0) { $0 + $1.seconds } / 60).hoursMinutes,
                                        bold: true
                                    )
                                    ForEach(list) { e in
                                        HStack {
                                            Text("\(Fmt.clock.string(from: e.start))–\(Fmt.clock.string(from: e.end))")
                                            Spacer()
                                            Text(detail(e))
                                        }
                                        .font(Theme.font(11))
                                        .padding(.leading, 16)
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(label).font(Theme.font(13, bold: true))
                    Text("this week").font(Theme.font(11))
                    Text((weekSecs / 60).hoursMinutes).font(Theme.font(48)).kerning(-1)
                    Text("\(Fmt.pomodoros(done)) over \(dayCount == 1 ? "1 day" : "\(dayCount) days")")
                    DottedRule()
                    LeaderRow(title: "all time", value: (allSecs / 60).hoursMinutes)
                    LeaderRow(title: "first logged", value: first.map { Fmt.dayMonth.string(from: $0) } ?? "–")
                    HStack(spacing: 10) {
                        Button("rename", action: onRename)
                            .buttonStyle(ClassicButtonStyle())
                        Button("export", action: onExport)
                            .buttonStyle(ClassicButtonStyle())
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .frame(width: 300, alignment: .leading)
                .background(Theme.paper)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                .background(Rectangle().fill(Theme.ink).offset(x: 2, y: 2))
            }
            .padding(24)
        }
    }

    private func detail(_ e: LogEntry) -> String {
        var s = "\(Int(e.minutes.rounded()))m"
        if e.addedMinutes > 0 { s += ", +\(e.addedMinutes)" }
        if !e.completed { s += ", stopped early" }
        return s
    }
}

// MARK: - Log

struct LogList: View {
    let entries: [LogEntry]
    let onRename: (RenameTarget) -> Void

    var body: some View {
        if entries.isEmpty {
            Text("nothing logged this week.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { e in
                        row(e)
                        DottedRule()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }

    private func row(_ e: LogEntry) -> some View {
        HStack(spacing: 14) {
            Text(Fmt.dayShort.string(from: e.start))
                .frame(width: 100, alignment: .leading)
            Text("\(Fmt.clock.string(from: e.start))–\(Fmt.clock.string(from: e.end))")
                .frame(width: 100, alignment: .leading)
            Group {
                if e.phase == .work {
                    Rectangle().fill(e.completed ? Theme.ink : Theme.paper)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                } else {
                    Rectangle().fill(Theme.dither)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                }
            }
            .frame(width: 9, height: 9)
            if e.phase == .work {
                Button { onRename(.block(e)) } label: {
                    Text(e.displayLabel).lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("click to rename")
            } else {
                Text(e.phase.title).lineLimit(1)
            }
            Spacer()
            if e.phase == .work && !e.completed { Text("stopped early") }
            if e.addedMinutes > 0 { Text("+\(e.addedMinutes)") }
            Text("\(Int(e.minutes.rounded())) min")
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if e.phase == .work { RenameMenu(entry: e, onRename: onRename) }
            Button("delete") { LogStore.shared.delete(e.id) }
        }
    }
}

// MARK: - Renaming

enum RenameTarget: Equatable {
    case block(LogEntry)
    case label(String)

    var current: String {
        switch self {
        case .block(let e): return e.label
        case .label(let l): return l
        }
    }

    func count(in entries: [LogEntry]) -> Int {
        switch self {
        case .block: return 1
        case .label(let l): return entries.filter { $0.phase == .work && $0.label.lowercased() == l.lowercased() }.count
        }
    }
}

/// Right-click menu items for a work block.
struct RenameMenu: View {
    let entry: LogEntry
    let onRename: (RenameTarget) -> Void

    var body: some View {
        Button("rename this block…") { onRename(.block(entry)) }
        if !entry.label.isEmpty {
            Button("rename every “\(entry.label)”…") { onRename(.label(entry.label)) }
        }
    }
}

/// Small window-style dialog over the stats window.
struct RenameDialog: View {
    let target: RenameTarget
    let count: Int
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var heading: String {
        switch target {
        case .block: return "rename this block"
        case .label(let l): return "rename every “\(l)”"
        }
    }

    private var note: String {
        switch target {
        case .block(let e):
            return "\(Fmt.dayShort.string(from: e.start)), \(Fmt.clock.string(from: e.start))–\(Fmt.clock.string(from: e.end))."
        case .label:
            return count == 1 ? "changes 1 block, all time." : "changes \(count) blocks, all time."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(Theme.font(13, bold: true))
            Text(note).font(Theme.font(11)).foregroundStyle(Theme.muted)
            TextField("", text: $text, prompt: Text("new label"))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                .focused($focused)
                .onSubmit { save() }
                .onChange(of: text) {
                    let lower = text.lowercased()
                    if lower != text { text = lower }
                }
            HStack(spacing: 10) {
                Spacer()
                Button("cancel", action: onCancel)
                    .buttonStyle(ClassicButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("rename") { save() }
                    .buttonStyle(ClassicButtonStyle(isDefault: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .background(Rectangle().fill(Theme.ink).offset(x: 2, y: 2))
        .onAppear {
            text = target.current
            focused = true
        }
    }

    private func save() {
        onSave(text)
    }
}
