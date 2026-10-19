import SwiftUI

extension DayActivityKind {
    var tint: Color {
        switch self {
        case .work: return .teal
        case .focus: return .indigo
        case .idle: return Color(red: 0.50, green: 0.72, blue: 0.38)
        case .away: return .orange
        case .moving: return .purple
        case .locked: return Color(red: 0.86, green: 0.45, blue: 0.24)
        case .unavailable: return .gray
        case .unknown: return Color(nsColor: .separatorColor).opacity(0.45)
        }
    }
}

struct HourlyActivityChart: View {
    let activity: DayActivity
    let now: Date
    @Binding var selectedHour: Date?
    private let height: CGFloat = 180
    static let legend: [DayActivityKind] = [.work, .focus, .idle, .away, .locked, .moving, .unavailable, .unknown]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("小时概览").font(.headline)
                Spacer()
                Text("每列 1 小时 · 从下往上 00 → 60 分").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack {
                    Text("60")
                    Spacer()
                    Text("30")
                    Spacer()
                    Text("00")
                }.font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 19, height: height)
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(activity.hours.enumerated()), id: \.element.id) { index, hour in
                        hourColumn(hour, labelVisible: index % 3 == 0 || index == activity.hours.count - 1)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 9) {
                ForEach(Self.legend, id: \.self) { kind in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(kind.tint).frame(width: 9, height: 9)
                        Text(kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("点击任一小时查看明细；短线标记当前时刻，未来时段留空。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func hourColumn(_ hour: DayActivityHour, labelVisible: Bool) -> some View {
        let current = hour.start <= now && now < hour.end
        let selected = selectedHour == hour.id
        return Button {
            selectedHour = selected ? nil : hour.id
        } label: {
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.025))
                        ForEach(hour.spans) { span in
                            let scale = height / hour.end.timeIntervalSince(hour.start)
                            Rectangle().fill(span.kind.tint)
                                .frame(width: geometry.size.width, height: max(0.3, span.duration * scale))
                                .offset(y: height - span.end.timeIntervalSince(hour.start) * scale)
                        }
                        if current {
                            Rectangle().fill(Color.primary).frame(height: 2)
                                .offset(y: max(0, height * (1 - now.timeIntervalSince(hour.start) / hour.end.timeIntervalSince(hour.start))))
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                }.frame(height: height)
                Text(labelVisible ? String(hour.label.prefix(2)) : " ")
                    .font(.system(size: 10, weight: current || selected ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(current || selected ? Color.accentColor : .secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(hour.label) 点，\(summary(hour))")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .help("\(hour.label):00\n\(summary(hour))")
    }
    private func summary(_ hour: DayActivityHour) -> String {
        let values = Self.legend.compactMap { kind -> String? in
            let seconds = hour.duration(kind)
            return seconds > 0 ? "\(kind.title) \(DurationText.short(seconds))" : nil
        }
        return values.isEmpty ? "尚未到来" : values.joined(separator: " · ")
    }
}

struct TimelinePage: View {
    @ObservedObject var app: AppController
    @ViewState var day = Date()
    @ViewState var selectedHour: Date?
    @ViewState var showDetails = false
    @ViewState private var showIdle = false
    private var range: DateInterval { Calendar.current.dateInterval(of: .day, for: day)! }
    var body: some View {
        let snapshot = app.timeline(day)
        let activity = snapshot.activity
        let items = snapshot.records(in: range, includeIdle: showIdle)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("一天的时间分布").font(.largeTitle.weight(.semibold))
                        Text("先看整天节奏，再查看每小时发生了什么。").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Button("今天") { day = Date() }
                }
                HStack(spacing: 10) {
                    MetricCard(title: "在工位 · 含专注与静默",
                               value: DurationText.short(activity.duration(.work) + activity.duration(.focus) + activity.duration(.idle)), color: .teal)
                    MetricCard(title: "其中专注", value: DurationText.short(activity.duration(.focus)), color: .indigo)
                    MetricCard(title: "离座 · 含锁屏与合盖",
                               value: DurationText.short(activity.duration(.away) + activity.duration(.locked) + activity.duration(.moving)),
                               color: .orange)
                }
                HourlyActivityChart(activity: activity, now: app.now, selectedHour: $selectedHour)
                if let hour = activity.hours.first(where: { $0.id == selectedHour }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(hour.start.formatted(date: .omitted, time: .shortened)) – \(endClock(hour.end))")
                                .font(.title3.weight(.semibold))
                            Text("最近优先").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("返回全天") { selectedHour = nil }
                        }
                        if hour.spans.isEmpty {
                            Text("这个小时还没有到来。").foregroundStyle(.secondary)
                        } else {
                            hourSummary(hour)
                            Toggle("显示阅读 / 静默子区间", isOn: $showIdle).toggleStyle(.checkbox)
                            let hourlyRecords = snapshot.records(in: hour.range, includeIdle: showIdle)
                            if hourlyRecords.isEmpty {
                                Text("这个小时没有状态记录。").foregroundStyle(.secondary)
                            }
                            detailRecords(hourlyRecords, snapshot: snapshot, in: hour.range)
                        }
                    }
                } else {
                    DisclosureGroup(isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("显示阅读 / 静默子区间", isOn: $showIdle).toggleStyle(.checkbox)
                            if items.isEmpty {
                                Text("这一天还没有记录。保持菜单栏运行，状态变化会自动出现。")
                                    .foregroundStyle(.secondary)
                            }
                            if showDetails { detailRecords(items, snapshot: snapshot, in: range) }
                        }.padding(.top, 12)
                    } label: {
                        HStack {
                            Text("全天记录明细").font(.headline)
                            Text("\(items.count) 段 · 最近优先").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("专注和静默属于在工位时间，色块不重复累计；未记录不等于离开。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .onChange(of: day) { _, _ in selectedHour = nil }
        .navigationTitle("时间分布")
    }

    private func hourSummary(_ hour: DayActivityHour) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(HourlyActivityChart.legend.filter { hour.duration($0) > 0 }, id: \.self) { kind in
                Label("\(kind.title) \(DurationText.short(hour.duration(kind)))", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(kind == .unknown ? .secondary : kind.tint)
            }
        }
    }
    private func endClock(_ date: Date) -> String {
        date == range.end ? "24:00" : clock(date)
    }
    private func detailRecords(_ records: [Session], snapshot: DayTimelineSnapshot, in interval: DateInterval) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(records) { session in
                sessionRow(session, previousInterval: snapshot.previousAwayIntervals[session.id], in: interval)
            }
            let focuses = snapshot.focusRecords(in: interval)
            if !focuses.isEmpty { Text("专注明细 · 最近优先").font(.headline).padding(.top, 8) }
            ForEach(focuses) { focus in
                let duration = focus.segments.reduce(0) {
                    $0 + StatisticsService.overlap(start: $1.start, end: $1.end ?? focus.end ?? focus.pausedAt,
                                                   range: interval, now: app.now)
                }
                HStack {
                    Image(systemName: "scope").foregroundStyle(.indigo)
                    Text("\(clock(max(focus.start, interval.start))) → \(endClock(min(focus.end ?? app.now, interval.end)))")
                    Spacer()
                    Text("有效 \(DurationText.short(duration))")
                    Text(focus.completed ? "完成" : focus.end != nil ? "已结束" : focus.pausedAt != nil ? "暂停" : "进行中")
                        .foregroundStyle(.secondary)
                }.font(.callout).padding(12).background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    private func sessionRow(_ session: Session, previousInterval: TimeInterval?, in interval: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3).fill(session.kind.tint).frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.kind == .away ? app.settings.classification(seconds: session.duration(at: app.now)) : session.kind.title)
                            .font(.headline)
                        if session.recovered { Text("结束时间未知").font(.caption).foregroundStyle(.orange) }
                        Spacer()
                        Text(DurationText.short(StatisticsService.overlap(start: session.start, end: session.end, range: interval, now: app.now)))
                            .monospacedDigit()
                    }
                    HStack {
                        let ongoing = session.end == nil && app.now < interval.end
                        Text("\(clock(max(session.start, interval.start))) → \(ongoing ? "进行中" : endClock(min(session.end ?? app.now, interval.end)))")
                        if session.start < range.start || (session.end ?? app.now) > range.end {
                            Text("跨日 · 仅显示本日部分")
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                    if session.kind == .away {
                        HStack {
                            Menu(session.label.isEmpty ? "添加标签" : session.label) {
                                ForEach(AppSettings.labels, id: \.self) { label in Button(label) { app.label(session, label) } }
                                Button("清除标签") { app.label(session, "") }
                            }.fixedSize()
                            if let previousInterval {
                                Text("距上次离开 \(DurationText.short(previousInterval))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !session.note.isEmpty { Text(session.note).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding(14).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
