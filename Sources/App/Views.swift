import SwiftUI
import Charts
import ServiceManagement

// Resolve the property-wrapper type, rather than the Xcode 27 @State macro overload.
typealias ViewState<Value> = SwiftUI.State<Value>

extension WorkstationState {
    var tint: Color {
        switch self {
        case .active, .focus: return .teal
        case .away: return .orange
        case .moving: return .purple
        case .locked: return .orange
        default: return .secondary
        }
    }
}
extension SessionKind {
    var tint: Color {
        switch self {
        case .work: return .teal
        case .away: return .orange
        case .moving: return .purple
        case .locked: return .orange
        case .idle: return .blue
        default: return .gray
        }
    }
}
func clock(_ date: Date?) -> String { date?.formatted(date: .omitted, time: .standard) ?? "—" }

struct MetricCard: View {
    let title: String
    let value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(color).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FocusControls: View {
    @ObservedObject var app: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let focus = app.currentFocus {
                if focus.pausedAt != nil {
                    focusTime(focus, at: app.now)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        focusTime(focus, at: context.date)
                    }
                }
                HStack {
                    if focus.pausedAt != nil {
                        Button("继续专注") { app.resumeFocus() }.disabled(!app.state.atDesk)
                    } else {
                        Button("暂停") { app.pauseFocus() }
                    }
                    Button("结束") { app.endFocus() }
                }
                if focus.pausedAt != nil { Text("回来后，由你决定是否继续。").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("开始专注").font(.headline)
                HStack {
                    ForEach([25, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes)分") { app.startFocus(Double(minutes)) }
                            .disabled(!app.state.atDesk)
                    }
                }
                Button("自定义 · \(Int(app.settings.customFocusMinutes)) 分钟") { app.startFocus(app.settings.customFocusMinutes) }
                    .disabled(!app.state.atDesk)
            }
        }
    }
    private func focusTime(_ focus: FocusSession, at date: Date) -> some View {
        let remaining = max(0, focus.plannedDuration - focus.elapsed(at: date))
        return Text("\(focus.pausedAt == nil ? "专注" : "已暂停") · \(DurationText.short(remaining))")
            .font(.headline).monospacedDigit()
    }
}

struct ReminderBanner: View {
    @ObservedObject var app: AppController
    var body: some View {
        if let kind = app.pendingReminder, app.state.atDesk {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind == "water" ? "该喝水了" : kind == "focus" ? "专注完成，准备好就休息一下" :
                     kind == "breakGuide" ? "把鼠标移到已设置的息屏触发角，即可开始休息。" : "连续在工位有一阵了，可以起来活动一下")
                    .font(.headline)
                HStack {
                    if kind == "water" {
                        Button("+\(app.settings.waterPlan.servingML) mL") { app.drink() }
                        Button("15 分钟后") { app.snooze("water") }
                    } else if kind == "sedentary" {
                        Button("准备休息") { app.pendingReminder = "breakGuide" }
                        Button("15 分钟后") { app.snooze("sedentary") }
                        Button("忽略") { app.ignoreSedentary() }
                    } else {
                        Button("知道了") { app.pendingReminder = nil }
                    }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct MenuContent: View {
    @ObservedObject var app: AppController
    var availableHeight: CGFloat = 440
    @ViewState private var showReminder = false
    var body: some View {
        menuBody.frame(width: 340, height: availableHeight)
    }
    var menuBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("工位节奏", systemImage: "circle.dotted.circle").font(.headline)
                Spacer()
                Text(app.state.title).font(.caption).foregroundStyle(app.state.tint)
            }
            if availableHeight >= 440 {
            let today = app.today
            HStack(alignment: .firstTextBaseline) {
                summary("工位", DurationText.short(today.work))
                Spacer()
                summary("专注", DurationText.short(today.focus))
                Spacer()
                summary("离座", DurationText.short(today.leave))
            }
            }
            HStack {
                CompactFocusControls(app: app)
                Spacer(minLength: 0)
                if !app.errorMessage.isEmpty {
                    Button { app.openPage?("settings") } label: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.red) }
                        .help(app.errorMessage)
                }
                if app.pendingReminder != nil && app.state.atDesk {
                    Button("提醒") { showReminder = true }
                        .popover(isPresented: $showReminder) { ReminderBanner(app: app).frame(width: 290).padding(10) }
                }
            }.font(.caption)
            HydrationBottleCard(progress: app.waterProgress, feedback: app.hydrationFeedback,
                                compact: availableHeight < 440,
                                onRecord: { app.recordPresetDrink($0, amountML: $1) },
                                onUndo: { app.undoLastDrink() }, onSettings: { app.openPage?("settings") },
                                onTheme: { theme in app.updateWaterPlan { $0.themeID = theme.rawValue } },
                                onHistory: { app.openPage?("history") })
            RecentActivityCard(app: app, compact: availableHeight < 440)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button("时间线") { app.openPage?("timeline") }
                Button("花历与统计") { app.openPage?("history") }
                Button("设置") { app.openPage?("settings") }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }.font(.caption).buttonStyle(.plain).padding(.vertical, 3)
        }.controlSize(.small).padding(10)
    }
    private func summary(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

struct CompactFocusControls: View {
    @ObservedObject var app: AppController
    var body: some View {
        if let focus = app.currentFocus {
            if focus.pausedAt == nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("专注 \(DurationText.short(max(0, focus.plannedDuration - focus.elapsed(at: context.date))))").monospacedDigit()
                }
                Button("暂停") { app.pauseFocus() }
            } else {
                Text("专注已暂停")
                Button("继续") { app.resumeFocus() }.disabled(!app.state.atDesk)
            }
            Menu { Button("结束本次专注") { app.endFocus() } } label: { Image(systemName: "ellipsis") }
                .fixedSize()
        } else {
            Button { app.startFocus(25) } label: {
                Label("专注 25 分钟", systemImage: "scope")
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.teal.opacity(0.09), in: Capsule())
            }.buttonStyle(.plain).disabled(!app.state.atDesk)
            Menu("更多") {
                ForEach([45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) 分钟") { app.startFocus(Double(minutes)) }
                }
                Button("自定义 \(Int(app.settings.customFocusMinutes)) 分钟") { app.startFocus(app.settings.customFocusMinutes) }
            }.menuStyle(.borderlessButton).disabled(!app.state.atDesk).fixedSize()
        }
    }
}

final class NavigationModel: ObservableObject { @Published var page: String? = "today" }

struct MainView: View {
    @ObservedObject var app: AppController
    @ObservedObject var navigation: NavigationModel
    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.page) {
                Label("今日", systemImage: "sun.max").tag("today")
                Label("饮水与离座", systemImage: "clock").tag("records")
                Label("时间线", systemImage: "list.bullet.indent").tag("timeline")
                Label("长期统计", systemImage: "chart.bar.xaxis").tag("history")
                Label("设置", systemImage: "slider.horizontal.3").tag("settings")
                if app.settings.debugEnabled { Label("事件诊断", systemImage: "waveform.path.ecg").tag("debug") }
            }
            .navigationTitle("工位节奏")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(app.state.title, systemImage: "circle.fill").foregroundStyle(app.state.tint)
                    Text("记录节奏，适时休息").font(.caption).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 165, ideal: 185)
        } detail: {
            VStack(spacing: 0) {
                if !app.errorMessage.isEmpty {
                    Text(app.errorMessage).foregroundStyle(.red).padding().frame(maxWidth: .infinity).background(.red.opacity(0.08))
                }
                switch navigation.page {
                case "records": ActivityRecordsPage(app: app)
                case "timeline": TimelinePage(app: app)
                case "history": HistoryPage(app: app)
                case "settings": SettingsPage(app: app)
                case "debug": DebugPage(app: app)
                default: DashboardPage(app: app)
                }
            }
        }
        .tint(.teal)
        .frame(minWidth: 820, minHeight: 600)
    }
}

struct DashboardPage: View {
    @ObservedObject var app: AppController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今天的工作节奏").font(.largeTitle.weight(.semibold))
                        Text(Date().formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(app.state.title).foregroundStyle(app.state.tint).padding(10).background(app.state.tint.opacity(0.1), in: Capsule())
                }
                if app.settings.corner == "auto" && app.monitor.configuration.departureCorners.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("先确认你的离开触发角").font(.headline)
                        Text("支持“锁屏”或“使显示器进入睡眠”。锁屏、合盖和通过触发角主动息屏都计为离座。")
                        Button("打开设置与引导") { app.openPage?("settings") }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                ReminderBanner(app: app)
                HStack(alignment: .top, spacing: 18) {
                    HydrationBottleCard(progress: app.waterProgress, feedback: app.hydrationFeedback,
                                    onRecord: { app.recordPresetDrink($0, amountML: $1) },
                                    onUndo: { app.undoLastDrink() }, onSettings: { app.openPage?("settings") },
                                    onTheme: { theme in app.updateWaterPlan { $0.themeID = theme.rawValue } },
                                    onHistory: { app.openPage?("history") }, spacious: true)
                    VStack(alignment: .leading, spacing: 18) {
                        RecentActivityCard(app: app)
                        Divider()
                        FocusControls(app: app)
                    }.padding(16).frame(width: 230)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                }
                let s = app.today
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 12) {
                    MetricCard(title: "在工位 · 含阅读静默", value: DurationText.short(s.work), color: .teal)
                    MetricCard(title: "主动专注", value: DurationText.short(s.focus), color: .teal)
                    MetricCard(title: "离座 · 含锁屏与合盖", value: DurationText.short(s.leave), color: .orange)
                    MetricCard(title: "锁屏 / 合盖离座", value: "\(DurationText.short(s.locked)) / \(DurationText.short(s.moving))", color: .purple)
                    MetricCard(title: "离座次数 · 锁屏 \(s.lockLeaves) / 合盖 \(s.lidLeaves)", value: "\(s.breaks)")
                    MetricCard(title: "主动锁屏 · 快捷键/菜单 / 触发角",
                               value: "\(s.recentInputLockLeaves) / \(s.hotCornerLockLeaves)")
                    MetricCard(title: "喝水 / 完成番茄钟", value: "\(s.water) / \(s.pomodoros)")
                }
                Text("连续性").font(.title2.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 12) {
                    MetricCard(title: "最长连续在工位", value: DurationText.short(s.longestWork))
                    MetricCard(title: "平均工作区间", value: DurationText.short(s.averageWork))
                    MetricCard(title: "平均离座间隔", value: s.averageInterval > 0 ? DurationText.short(s.averageInterval) : "—")
                    MetricCard(title: "平均离座时长", value: DurationText.short(s.averageBreak))
                    MetricCard(title: "短休 / 长休（已完成）", value: "\(s.shortBreaks) / \(s.longBreaks)")
                    MetricCard(title: "阅读 / 无操作", value: DurationText.short(s.idle))
                }
                HStack {
                    Text("首次离开 \(clock(s.firstLeave))")
                    Spacer()
                    Text("最后离开 \(clock(s.lastLeave))")
                }.font(.callout).foregroundStyle(.secondary)
                Text("在工位是行为推断，包含阅读与静默；专注是它的子集。锁屏、合盖与主动离开统一计为离座，同时保留各自类型。设备睡眠与未观测不计为离座。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.navigationTitle("今日")
    }
}
