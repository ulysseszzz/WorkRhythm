import SwiftUI
import Charts
import ServiceManagement

struct HistoryPage: View {
    @ObservedObject var app: AppController
    @ViewState private var scale = "Week"
    @ViewState private var date = Date()
    var days: [Date] {
        let calendar = Calendar.current
        let range = calendar.dateInterval(of: scale == "Day" ? .day : scale == "Week" ? .weekOfYear : .month, for: date)!
        var result: [Date] = []; var value = range.start
        while value < range.end && value <= Date() {
            result.append(value); value = calendar.date(byAdding: .day, value: 1, to: value)!
        }
        return result
    }
    var summaries: [DailySummary] { days.map(app.summary) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("长期节奏").font(.largeTitle.weight(.semibold))
                    Spacer()
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Picker("范围", selection: $scale) {
                        ForEach(["Day", "Week", "Month"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 220)
                }
                let values = summaries
                HStack(spacing: 12) {
                    MetricCard(title: "在工位", value: DurationText.short(values.reduce(0) { $0 + $1.work }), color: .teal)
                    MetricCard(title: "专注", value: DurationText.short(values.reduce(0) { $0 + $1.focus }), color: .teal)
                    MetricCard(title: "主动离开", value: DurationText.short(values.reduce(0) { $0 + $1.away }), color: .orange)
                }
                Chart(values, id: \.date) { s in
                    BarMark(x: .value("日期", s.date, unit: .day), y: .value("小时", s.work / 3600))
                        .foregroundStyle(by: .value("状态", "在工位"))
                    BarMark(x: .value("日期", s.date, unit: .day), y: .value("小时", s.away / 3600))
                        .foregroundStyle(by: .value("状态", "离开"))
                    BarMark(x: .value("日期", s.date, unit: .day), y: .value("小时", s.moving / 3600))
                        .foregroundStyle(by: .value("状态", "合盖"))
                }
                .chartForegroundStyleScale(["在工位": Color.teal, "离开": .orange, "合盖": .purple])
                .frame(height: 235)
                Text("每日原始指标").font(.title2.weight(.semibold))
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 14) {
                        GridRow {
                            ForEach(["日期", "在工位", "专注", "离开", "合盖", "离开次数", "平均工作", "工作中位数", "最长工作", "平均离开", "平均间隔", "次 / 工位小时", "喝水", "番茄钟"], id: \.self) {
                                Text($0).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(values, id: \.date) { s in
                            GridRow {
                                Text(s.date.formatted(.dateTime.month().day()))
                                Text(DurationText.short(s.work))
                                Text(DurationText.short(s.focus))
                                Text(DurationText.short(s.away))
                                Text(DurationText.short(s.moving))
                                Text("\(s.breaks)")
                                Text(DurationText.short(s.averageWork))
                                Text(DurationText.short(s.medianWork))
                                Text(DurationText.short(s.longestWork))
                                Text(DurationText.short(s.averageBreak))
                                Text(s.averageInterval > 0 ? DurationText.short(s.averageInterval) : "—")
                                Text(String(format: "%.2f", s.breaksPerWorkHour))
                                Text("\(s.waterML) mL · \(s.water) 次")
                                Text("\(s.pomodoros)")
                            }.font(.callout).monospacedDigit()
                        }
                    }.padding(16)
                }.background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                Text("触发时段分布").font(.title2.weight(.semibold))
                let hourly = (0..<24).map { hour in values.reduce(0) { $0 + $1.hourly[hour] } }
                Chart(0..<24, id: \.self) { hour in
                    BarMark(x: .value("小时", hour), y: .value("次数", hourly[hour])).foregroundStyle(.orange)
                }.chartXAxis { AxisMarks(values: [0, 6, 9, 12, 15, 18, 21, 23]) }.frame(height: 170)
                let selected = app.summary(date)
                Text("所选日的离开间隔 · \(date.formatted(date: .abbreviated, time: .omitted))").font(.headline)
                HStack {
                    MetricCard(title: "平均", value: selected.averageInterval > 0 ? DurationText.short(selected.averageInterval) : "—")
                    MetricCard(title: "中位数", value: selected.medianInterval > 0 ? DurationText.short(selected.medianInterval) : "—")
                    MetricCard(title: "最短 / 最长", value: selected.minInterval > 0 ? "\(DurationText.short(selected.minInterval)) / \(DurationText.short(selected.maxInterval))" : "—")
                }
                Text("离开间隔按同一天相邻两次 Away 开始计算。累计时长按当地日历切分；跨午夜的离开次数归开始日。平均离开排除进行中与观测中断记录。没有将这些原始指标合成为“效率评分”。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("导出全部 CSV") { app.export("csv") }
                    Button("备份 SQLite 数据库") { app.export("backup") }
                }
            }.padding(28)
        }.navigationTitle("统计")
    }
}

struct SettingsPage: View {
    @ObservedObject var app: AppController
    func binding<T>(_ path: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { app.settings[keyPath: path] }, set: { app.settings[keyPath: path] = $0 })
    }
    var body: some View {
        Form {
            Section("锁屏 / 息屏触发角") {
                Text(app.cornerDescription).font(.callout).foregroundStyle(.secondary)
                Picker("用于主动离开的角", selection: binding(\.corner)) {
                    Text("自动读取系统设置").tag("auto")
                    ForEach(HotCornerConfiguration.corners, id: \.self) { corner in Text(HotCornerConfiguration.titles[corner]!).tag(corner) }
                }
                Text("“锁屏”和“使显示器进入睡眠”都代表主动离开。手动选择表示你确认该角用于离开；本工具不会修改 Dock 设置。多显示器按各屏幕实际坐标匹配。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开 macOS 触发角设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                    }
                    Button("重新检测") { app.monitor.refreshConfiguration(); app.revision += 1 }
                }
            }
            Section("检测与校准") {
                Toggle("自动检测窗口", isOn: Binding(get: { app.settings.detectionWindow == 0 }, set: { app.settings.detectionWindow = $0 ? 0 : 1.5 }))
                if app.settings.detectionWindow > 0 {
                    HStack {
                        Slider(value: binding(\.detectionWindow), in: 0.2...5, step: 0.1)
                        Text(String(format: "%.1f 秒", app.settings.detectionWindow)).monospacedDigit().frame(width: 70)
                    }
                }
                Text("当前窗口 \(String(format: "%.2f", app.settings.effectiveWindow))s；\(app.settings.calibratedWindow == nil ? "默认 1.5s 尚未经过你的真实触发校准" : "已使用你确认的样本校准")。锁屏或息屏后另等待 1.25s 排除竞争性系统事件。")
                    .font(.caption).foregroundStyle(.secondary)
                if let delta = app.machine.candidateAge, delta >= 0, delta <= 5 {
                    Text("最近候选：进入角到锁屏 / 息屏 \(String(format: "%.3f", delta))s")
                    Button("确认最近一次确实是触发角，并校准窗口") { app.calibrateFromLastCandidate() }
                }
                Text("锁屏角、⌃⌘Q 和 Apple 菜单手动锁屏都会开始离开，解锁结束；自动锁屏、屏保、系统睡眠和合盖不会。快捷键与菜单通过锁屏前 5 秒内的聚合输入推断，来源并非 macOS 直接提供。")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("静默阈值 \(Int(app.settings.idleMinutes)) 分钟", value: binding(\.idleMinutes), in: 1...60, step: 1)
            }
            Section("专注") {
                Stepper("自定义专注 \(Int(app.settings.customFocusMinutes)) 分钟", value: binding(\.customFocusMinutes), in: 1...240, step: 1)
                Picker("触发角离开时", selection: binding(\.pauseFocusOnAway)) {
                    Text("暂停，回来后询问继续").tag(true)
                    Text("结束本次专注").tag(false)
                }
                Text("合盖、锁屏、屏幕睡眠和系统睡眠会暂停专注。无操作不等于不专注，不会自动结束番茄钟。").font(.caption).foregroundStyle(.secondary)
            }
            Section("喝水主题与每日计划") {
                Picker("陪伴主题", selection: Binding(get: { app.settings.waterPlan.theme },
                    set: { theme in app.updateWaterPlan { $0.themeID = theme.rawValue } })) {
                    ForEach(HydrationTheme.allCases, id: \.self) { theme in
                        Label(theme.title, systemImage: theme.symbol).tag(theme)
                    }
                }
                Toggle("水波与微风动画", isOn: Binding(get: { app.settings.waterPlan.motionEnabled },
                    set: { enabled in app.updateWaterPlan { $0.ambientMotion = enabled } }))
                Text("水瓶与花园随今日水量成长，饮品组合决定水色和花型。点“配方图鉴”可预览全部花朵。动画只在可见时运行；低电量模式下降频，过热或开启“减少动态效果”时静止。")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("每日目标 \(app.settings.waterPlan.targetML) mL",
                        value: Binding(get: { app.settings.waterPlan.targetML },
                                       set: { value in app.updateWaterPlan { $0.dailyTargetML = value } }),
                        in: 200...6000, step: 100)
                Stepper("预计每天 \(app.settings.waterPlan.targetCount) 次",
                        value: Binding(get: { app.settings.waterPlan.targetCount },
                                       set: { value in app.updateWaterPlan { $0.plannedDrinks = value } }),
                        in: 1...30)
                Text("按 \(app.settings.waterPlan.targetML) mL / \(app.settings.waterPlan.targetCount) 次分配：每次参考 \(app.settings.waterPlan.suggestedServingML) mL")
                    .foregroundStyle(.teal)
                if app.settings.waterPlan.targetML / app.settings.waterPlan.targetCount > 2000 {
                    Text("单次记录上限为 2000 mL，建议增加计划次数。").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("每次使用建议量", isOn: Binding(get: { app.settings.waterPlan.customServingML == nil },
                    set: { automatic in app.updateWaterPlan { $0.customServingML = automatic ? nil : $0.suggestedServingML } }))
                if app.settings.waterPlan.customServingML != nil {
                    Stepper("每次点击记录 \(app.settings.waterPlan.servingML) mL",
                            value: Binding(get: { app.settings.waterPlan.servingML },
                                           set: { value in app.updateWaterPlan { $0.customServingML = value } }),
                            in: 10...2000, step: 10)
                }
                Text("选择饮品和滑杆容量后，点记录即可。图案仅展示，不再点击记账。误点可撤销，花型与水色同步回退。默认 1600 mL / 8 次只是可调整的计划示例。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("旧版打卡只保留次数、水量未知。修改每次量只影响之后的记录，不会改写历史水量。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("各饮品记住的容量") {
                ForEach(DrinkPreset.displayOrder, id: \.self) { preset in
                    Stepper("\(preset.shortTitle) · \(DrinkAmount.sliderValue(app.settings.waterPlan.servingML(for: preset))) mL",
                            value: Binding(get: { DrinkAmount.sliderValue(app.settings.waterPlan.servingML(for: preset)) },
                                           set: { amount in app.updateWaterPlan { $0.setServingML(amount, for: preset) } }),
                            in: 150...600, step: 150)
                }
                Button("恢复默认容量") { app.updateWaterPlan { $0.presetVolumesML = nil } }
                Text("菜单滑杆每格 150 mL，提供 150 / 300 / 450 / 600 mL 四档，点刻度也能选量。切换类型保留已选容量，点击记录才记账。再次打开菜单时沿用上次饮品及容量。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("旧容量仅在滑杆显示时就近取档并限到 600 mL，历史记录不变。饮品均按记录体积合计。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("轻量提醒") {
                Toggle("喝水提醒", isOn: binding(\.hydrationEnabled))
                Stepper("喝水间隔 \(Int(app.settings.hydrationMinutes)) 分钟", value: binding(\.hydrationMinutes), in: 15...240, step: 15)
                Toggle("久坐提醒", isOn: binding(\.sedentaryEnabled))
                Stepper("连续在工位 \(Int(app.settings.sedentaryMinutes)) 分钟后提醒", value: binding(\.sedentaryMinutes), in: 15...180, step: 15)
                Stepper("返回后等待 \(Int(app.settings.returnGraceSeconds / 60)) 分钟", value: binding(\.returnGraceSeconds), in: 60...180, step: 60)
                Text("Away、Moving、锁屏、息屏、睡眠时不提醒。专注时暂停久坐提醒；喝水仅在额外超时一个完整喝水周期后提醒。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(app.notificationStatus).foregroundStyle(.secondary)
                    Button("允许系统通知") { app.requestNotifications() }
                    Button("通知设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                }
            }
            Section("Away 初步分类 · 分钟上界") {
                ForEach(0..<4, id: \.self) { i in
                    Stepper("\(["Micro", "Short", "Long", "Meal / Long Away Candidate"][i]) < \(Int(app.settings.breakThresholds[i])) 分钟",
                            value: Binding(get: { app.settings.breakThresholds[i] }, set: { value in
                        let lower = i == 0 ? 1 : app.settings.breakThresholds[i - 1] + 1
                        let upper = i == 3 ? 720 : app.settings.breakThresholds[i + 1] - 1
                        app.settings.breakThresholds[i] = min(upper, max(lower, value))
                    }), in: 1...720, step: 1)
                }
                Text("分类只是候选，不代表厕所、吃饭等真实原因。可在时间线手动添加标签。").font(.caption).foregroundStyle(.secondary)
            }
            Section("启动、隐私与数据") {
                Toggle("登录时启动", isOn: binding(\.launchAtLogin))
                HStack {
                    Text(app.loginStatus).foregroundStyle(.secondary)
                    Button("登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("仅本地 SQLite。无需辅助功能、输入监控、自动化或屏幕录制权限。只监听鼠标事件与系统状态，读取输入空闲秒数；不读取键盘内容、截图、应用内容或剪贴板。")
                    .font(.callout).foregroundStyle(.secondary)
                Text(app.repository.url.path).font(.caption.monospaced()).textSelection(.enabled)
                HStack {
                    Button("打开数据文件夹") { NSWorkspace.shared.open(app.repository.url.deletingLastPathComponent()) }
                    Button("备份数据") { app.export("backup") }
                    Button("导出 CSV") { app.export("csv") }
                }
                Toggle("显示事件诊断页面", isOn: binding(\.debugEnabled))
                Text("必要事件日志保留 30 天，只在角落候选时保存鼠标坐标；不会持续记录鼠标轨迹。工作记录保留至你自行删除数据库。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("设置")
    }
}

struct DebugPage: View {
    @ObservedObject var app: AppController
    @ViewState private var filter = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("事件诊断").font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新") { app.refreshEvents() }
                Button("导出日志 JSON") { app.export("debug") }
            }
            Text(verbatim: "状态：\(app.state.rawValue) · display=\(app.machine.displayAwake ? "awake" : "asleep") · systemSleep=\(app.machine.sleeping) · locked=\(app.machine.locked)")
                .font(.callout.monospaced())
            Text("鼠标回调 \(app.monitor.mouseEventCount) · 最后回调 \(clock(app.monitor.lastMouseEvent)) · IOKit 注册结果 \(app.monitor.lidRegistration) · 合盖 \(String(describing: app.monitor.lastLid))")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(app.lastDecision).font(.caption.monospaced()).textSelection(.enabled)
            Text("验证：分别使用锁屏/息屏触发角、⌃⌘Q 和 Apple 菜单锁屏，返回后检查 classification / state_transition；再用自动锁屏、自然息屏、屏保、系统睡眠和合盖验证排除条件。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("筛选日志", text: $filter)
            List(app.events.filter { filter.isEmpty || $0.type.localizedCaseInsensitiveContains(filter) || $0.metadata.localizedCaseInsensitiveContains(filter) }) { event in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(event.timestamp.formatted(.iso8601))  \(event.type)").font(.caption.weight(.semibold))
                    Text(event.metadata).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
        }.padding(24).navigationTitle("诊断")
    }
}
