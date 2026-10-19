import SwiftUI

extension GardenRecipe {
    var tint: Color { let c = rgb; return Color(red: c.0, green: c.1, blue: c.2) }
}

struct HydrationBottleCard: View {
    let progress: HydrationProgress
    var feedback = ""
    var compact = false
    var onRecord: (DrinkPreset, Int) -> Void
    var onUndo: () -> Void
    var onSettings: () -> Void
    var onHistory: () -> Void = {}
    var spacious = false
    @ViewState private var showComposer = false
    @ViewState private var showRecipes = false
    private var recipe: GardenRecipe { progress.garden.recipe }
    private var selection: DrinkPreset { progress.plan.selectedDrink }
    private var selectedML: Int { DrinkAmount.bounded(progress.plan.servingML(for: selection)) }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("今日花园").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: onHistory) {
                    Label("花历", systemImage: "calendar")
                }
                .help("查看每天开出的花和奖杯")
                Button("图鉴") { showRecipes = true }
                    .popover(isPresented: $showRecipes) { RecipeCatalog(garden: progress.garden) }
                Button(action: onSettings) { Image(systemName: "slider.horizontal.3") }
                    .help("调整饮水计划")
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            HStack(spacing: spacious ? 16 : 12) {
                ZStack {
                    Circle().fill(recipe.tint.opacity(0.07))
                        .frame(width: spacious ? 154 : 102, height: spacious ? 154 : 102)
                    HydrationScene(theme: .flowers, fraction: progress.fraction,
                                   motionEnabled: progress.plan.motionEnabled, recipe: recipe)
                        .frame(width: spacious ? 154 : compact ? 86 : 98,
                               height: spacious ? 184 : compact ? 100 : 116)
                }.frame(width: spacious ? 158 : 114, height: spacious ? 184 : compact ? 100 : 116)
                VStack(alignment: .leading, spacing: 5) {
                    Text(progress.garden.hasDrinks ? recipe.title : "等你来浇灌")
                        .font(.system(size: spacious ? 19 : 14, weight: .semibold)).foregroundStyle(recipe.tint)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(progress.totalML)").font(.system(size: spacious ? 34 : 25, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.65)
                        Text("mL").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text("目标 \(progress.plan.targetML) · \(Int(progress.fraction * 100))%")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    Text(progress.completed ? "今日已达标 · 花开留念" : "再饮 \(max(0, progress.plan.targetML - progress.totalML)) mL 达标")
                        .font(.system(size: 10)).foregroundStyle(recipe.tint)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Button { showComposer = true } label: {
                    HStack(spacing: 5) {
                        Text("\(selection.shortTitle) · \(selectedML) mL")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help("更换饮品和容量")
                    .popover(isPresented: $showComposer, arrowEdge: .bottom) {
                        DrinkComposer(plan: progress.plan, tint: recipe.tint) { drink, ml in
                            onRecord(drink, ml)
                            showComposer = false
                        }
                    }
                Button { onRecord(selection, selectedML) } label: {
                    Label("记录", systemImage: "plus").frame(width: 70, height: 28)
                        .foregroundStyle(.white)
                        .background(recipe.tint.gradient, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityLabel("记录\(selection.shortTitle) \(selectedML) 毫升")
            }.font(.system(size: 12, weight: .medium))
            HStack(spacing: 4) {
                Text(feedback.isEmpty ? "今日 \(progress.count) 次饮用" : feedback)
                    .lineLimit(1).help(feedback)
                Spacer(minLength: 0)
                Button("撤销", action: onUndo).buttonStyle(.plain).disabled(progress.lastEntry == nil)
                    .help("撤销今天最近一次饮用")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(10)
        .background {
            HydrationWaterBackdrop(fraction: progress.fraction,
                                   motionEnabled: progress.plan.motionEnabled, recipe: recipe)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(recipe.tint.opacity(0.12), lineWidth: 0.5))
    }
}

/// Editing lives in a separate popover; choosing a drink never writes an event.
struct DrinkComposer: View {
    let plan: HydrationPlan
    let tint: Color
    var onRecord: (DrinkPreset, Int) -> Void
    @ViewState private var selection: DrinkPreset
    @ViewState private var amount: Int
    init(plan: HydrationPlan, tint: Color, onRecord: @escaping (DrinkPreset, Int) -> Void) {
        self.plan = plan; self.tint = tint; self.onRecord = onRecord
        _selection = ViewState(initialValue: plan.selectedDrink)
        _amount = ViewState(initialValue: DrinkAmount.bounded(plan.servingML(for: plan.selectedDrink)))
    }
    private var selectedML: Int { DrinkAmount.bounded(amount) }
    private var nodes: [Int] { selection.amountNodes }
    private var sliderAmount: Binding<Double> {
        Binding(
            get: { DrinkAmount.sliderPosition(for: selectedML, nodes: nodes) },
            set: { amount = DrinkAmount.amount(atSliderPosition: $0, nodes: nodes) }
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("记录饮品").font(.headline)
                Spacer()
                Text("选择后确认记录").font(.caption).foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<2) { row in
                    GridRow {
                        ForEach(Array(DrinkPreset.displayOrder[(row * 3)..<(row * 3 + 3)]), id: \.self) { drink in
                            Button { selection = drink } label: {
                                Text(drink.shortTitle).font(.system(size: 11, weight: selection == drink ? .semibold : .regular))
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(selection == drink ? tint.opacity(0.20) : Color.primary.opacity(0.035),
                                                in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).accessibilityLabel("选择\(drink.shortTitle)，不记录")
                                .accessibilityAddTraits(selection == drink ? [.isSelected] : [])
                        }
                    }
                }
            }
            VStack(spacing: 2) {
                HStack {
                    Text("容量 · 可自由拖动").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(selectedML) mL").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                Slider(value: sliderAmount, in: 0...Double(nodes.count - 1))
                    .tint(tint)
                    .accessibilityLabel("\(selection.shortTitle)容量，可连续调整")
                    .accessibilityValue("\(selectedML) 毫升")
                GeometryReader { geometry in
                    ForEach(Array(nodes.enumerated()), id: \.element) { index, ml in
                        Button("\(ml)") { amount = ml }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: selectedML == ml ? .bold : .regular))
                            .foregroundStyle(selectedML == ml ? tint : .secondary)
                            .frame(width: 46, height: 18)
                            .contentShape(Rectangle())
                            .position(x: 10 + CGFloat(index) / CGFloat(nodes.count - 1) * (geometry.size.width - 20), y: 9)
                            .accessibilityLabel("选择\(selection.shortTitle) \(ml) 毫升节点")
                    }
                }.frame(height: 18)
                HStack(spacing: 6) {
                    Text("精确容量").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    TextField("容量", value: $amount, format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .frame(width: 58)
                        .accessibilityLabel("实际饮用毫升数")
                    Text("mL").font(.system(size: 10)).foregroundStyle(.secondary)
                    Stepper("", value: $amount, in: DrinkAmount.range, step: 10)
                        .labelsHidden().fixedSize()
                }.padding(.top, 4)
            }
            Button { onRecord(selection, selectedML) } label: {
                Text("记录\(selection.shortTitle) · \(selectedML) mL")
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
            }.buttonStyle(.borderedProminent).tint(tint)
        }
        .padding(16).frame(width: 300)
        .onChange(of: selection) { _, drink in
            amount = DrinkAmount.bounded(plan.servingML(for: drink))
        }
    }
}

struct RecipeCatalog: View {
    let garden: DrinkGarden
    @ViewState private var selected: GardenRecipe = .dew
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日配方图鉴").font(.headline)
                Spacer()
                Text("\(garden.unlocked.count) / \(GardenRecipe.allCases.count)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                HydrationScene(theme: .flowers, fraction: 1, motionEnabled: true, recipe: selected)
                    .frame(width: 110, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.title).font(.headline).foregroundStyle(selected.tint)
                    Text(selected.formula).font(.caption)
                    Text(garden.unlocked.contains(selected) ? "今日已点亮" : "配方预览").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("当天记录过配方中的饮品就会点亮；水量决定成长，组合决定花型与水色。").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(GardenRecipe.allCases, id: \.self) { recipe in
                        Button { selected = recipe } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title).font(.system(size: 11, weight: .semibold))
                                Text(recipe.formula).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(garden.unlocked.contains(recipe) ? "✓ 今日已点亮" : "点选看花型")
                                    .font(.system(size: 10)).foregroundStyle(recipe.tint)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                .background(recipe.tint.opacity(selected == recipe ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 215)
            Text("自由预览不写入饮水记录；撤销和跨日会同步更新今日配方。").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(16).frame(width: 370)
            .onAppear { selected = garden.recipe }
    }
}
