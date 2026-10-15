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
        let screens = app.screenRecords(app.now)
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
                Image(systemName: "display").foregroundStyle(.secondary).frame(width: 15).padding(.top, 2)
                VStack(spacing: 3) {
                    if screens.isEmpty { empty("还没有屏幕变化") }
                    ForEach(screens.prefix(compact ? 1 : 2)) { screen in
                        line(time: recordTime(screen.timestamp), title: screen.title, value: "")
                            .help("\(clock(screen.timestamp)) · \(screen.title)")
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
        let screens = app.screenRecords(day)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("饮水与屏幕记录").font(.largeTitle.weight(.semibold))
                        Text("按时间回看每一次饮用与屏幕变化。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Button("今天") { day = app.now }
                }
                HStack(spacing: 12) {
                    MetricCard(title: "饮用总量", value: "\(drinks.compactMap(\.amountML).reduce(0, +)) mL", color: .teal)
                    MetricCard(title: "饮用次数", value: "\(drinks.count)")
                    MetricCard(title: "屏幕事件", value: "\(screens.count)")
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
                    recordColumn(title: "屏幕", symbol: "display", count: screens.count) {
                        if screens.isEmpty { placeholder("这一天没有可用的屏幕事件", symbol: "display") }
                        ForEach(screens) { screen in
                            HStack(spacing: 10) {
                                Text(clock(screen.timestamp)).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: screen.symbol)
                                    .foregroundStyle(screen.inactive ? Color.secondary : .teal).frame(width: 16)
                                Text(screen.title)
                                Spacer(minLength: 0)
                            }.font(.system(size: 12)).padding(.vertical, 9)
                            Divider()
                        }
                    }
                }
                HStack {
                    Text("屏幕事件保留最近 30 天；工位与离开区间可在时间线长期查看。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("查看时间线") { app.openPage?("timeline") }
                }
            }.padding(24)
        }.navigationTitle("饮水与屏幕记录")
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
