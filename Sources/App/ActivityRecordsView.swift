import SwiftUI

private func recordTime(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
}

extension HydrationEvent {
    var shortDrinkTitle: String { DrinkPreset(rawValue: drinkPresetID ?? "")?.shortTitle ?? "饮水" }
    var volumeText: String { amountML.map { "\($0) mL" } ?? "未记容量" }
}

struct RecentActivityCard: View {
    @ObservedObject var app: AppController
    var compact = false
    var body: some View {
        let drinks = ActivityRecords.drinks(app.water, day: app.now, now: app.now)
        let departures = ActivityRecords.departures(app.sessions, day: app.now, now: app.now)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("今日记录").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { app.openPage?("records") } label: {
                    HStack(spacing: 3) { Text("全部"); Image(systemName: "chevron.right").font(.system(size: 8)) }
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.system(size: 10))
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "drop.fill").foregroundStyle(.teal).frame(width: 15).padding(.top, 2)
                VStack(spacing: 3) {
                    if drinks.isEmpty { empty("还没有饮水记录") }
                    ForEach(drinks.prefix(compact ? 1 : 2)) { drink in
                        line(time: recordTime(drink.timestamp), title: drink.shortDrinkTitle, value: drink.volumeText)
                            .help("\(clock(drink.timestamp)) · \(drink.shortDrinkTitle) · \(drink.volumeText)")
                    }
                }
            }
            Divider().opacity(0.5)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "figure.walk").foregroundStyle(.orange).frame(width: 15).padding(.top, 2)
                VStack(spacing: 3) {
                    if departures.isEmpty { empty("还没有离座记录") }
                    ForEach(departures.prefix(compact ? 1 : 2)) { departure in
                        line(time: recordTime(departure.start), title: departure.kind.title,
                             value: departure.end == nil ? "进行中" : DurationText.short(departure.duration(at: app.now)))
                            .help("\(clock(departure.start)) · \(departure.kind.title)")
                    }
                }
            }
        }.font(.system(size: 11)).padding(.horizontal, 3)
    }
    private func empty(_ title: String) -> some View {
        Text(title).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).frame(height: 15)
    }
    private func line(time: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(time).monospacedDigit().foregroundStyle(.secondary).frame(width: 37, alignment: .leading)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }.frame(height: 15)
    }
}

struct ActivityRecordsPage: View {
    @ObservedObject var app: AppController
    @ViewState var day = Date()
    var body: some View {
        let drinks = ActivityRecords.drinks(app.water, day: day, now: app.now)
        let departures = ActivityRecords.departures(app.sessions, day: day, now: app.now)
        let lockLeaves = departures.filter { $0.kind == .lock }.count
        let lidLeaves = departures.filter { $0.kind == .lid }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("饮水与离座记录").font(.largeTitle.weight(.semibold))
                        Text("锁屏、合盖与主动离开都计为离座。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Button("今天") { day = app.now }
                }
                HStack(spacing: 12) {
                    MetricCard(title: "饮用总量", value: "\(drinks.compactMap(\.amountML).reduce(0, +)) mL", color: .teal)
                    MetricCard(title: "饮用次数", value: "\(drinks.count)")
                    MetricCard(title: "离座次数", value: "\(departures.count)", color: .orange)
                    MetricCard(title: "锁屏 / 合盖", value: "\(lockLeaves) / \(lidLeaves)")
                }
                HStack(alignment: .top, spacing: 16) {
                    recordColumn(title: "饮水", symbol: "drop.fill", count: drinks.count) {
                        if drinks.isEmpty { placeholder("这一天没有饮水记录", symbol: "drop") }
                        ForEach(drinks) { drink in
                            HStack(spacing: 10) {
                                Text(clock(drink.timestamp)).monospacedDigit().foregroundStyle(.secondary)
                                Text(drink.shortDrinkTitle)
                                Spacer(minLength: 0)
                                Text(drink.volumeText).fontWeight(.medium)
                            }.font(.system(size: 12)).padding(.vertical, 9)
                            Divider()
                        }
                    }
                    recordColumn(title: "离座", symbol: "figure.walk", count: departures.count) {
                        if departures.isEmpty { placeholder("这一天没有离座记录", symbol: "figure.walk") }
                        ForEach(departures) { departure in
                            HStack(spacing: 10) {
                                Text(clock(departure.start)).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: departure.kind.symbol).foregroundStyle(.orange).frame(width: 16)
                                Text(departure.kind.title)
                                Spacer(minLength: 0)
                                Text(departure.end == nil ? "进行中" : DurationText.short(departure.duration(at: app.now)))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }.font(.system(size: 12)).padding(.vertical, 9)
                            Divider()
                        }
                    }
                }
                HStack {
                    Text("离座记录随时间线长期保留；解锁、开盖只结束离座，不重复计次。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("查看时间线") { app.openPage?("timeline") }
                }
            }.padding(24)
        }.navigationTitle("饮水与离座记录")
    }
    private func recordColumn<Content: View>(title: String, symbol: String, count: Int,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Text("\(count) 条 · 最近优先").font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 6)
            LazyVStack(alignment: .leading, spacing: 0, content: content)
        }.frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
    private func placeholder(_ title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.caption)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
