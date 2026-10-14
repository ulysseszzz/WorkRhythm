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
    var onTheme: (HydrationTheme) -> Void = { _ in }
    @ViewState private var selection: DrinkPreset = .waterBottle
    @ViewState private var amount = 300.0
    @ViewState private var showRecipes = false
    private var recipe: GardenRecipe { progress.garden.recipe }
    private var selectedML: Int { DrinkAmount.sliderValue(Int(amount)) }
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                ForEach(HydrationTheme.allCases, id: \.self) { theme in
                    Button { onTheme(theme) } label: {
                        Label(theme.title, systemImage: theme.symbol)
                            .font(.system(size: 11, weight: .medium)).padding(.vertical, 2).padding(.horizontal, 7)
                            .background(progress.plan.theme == theme ? recipe.tint.opacity(0.15) : .clear,
                                        in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(progress.plan.theme == theme ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
                Button("配方图鉴") { showRecipes = true }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
                    .popover(isPresented: $showRecipes) { RecipeCatalog(garden: progress.garden) }
            }
            HStack(spacing: 10) {
                HydrationScene(theme: progress.plan.theme, fraction: progress.fraction,
                                   motionEnabled: progress.plan.motionEnabled, recipe: recipe)
                        .frame(width: compact ? 38 : 46, height: compact ? 46 : 60)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(progress.totalML)").font(.system(size: compact ? 23 : 27, weight: .semibold, design: .rounded))
                        Text("/ \(progress.plan.targetML) mL").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(progress.garden.hasDrinks ? recipe.title : "今天的花园，等你来浇灌")
                        if progress.completed {
                            Image(systemName: "trophy.fill").accessibilityLabel("今日已获得开花奖杯")
                        }
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(recipe.tint)
                    HStack {
                        Text("\(progress.count) 次 · \(Int(progress.fraction * 100))%").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("计划", action: onSettings).buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(DrinkPreset.displayOrder, id: \.self) { drink in
                    Button {
                        selection = drink
                    } label: {
                        Text(drink.shortTitle).font(.system(size: 11, weight: selection == drink ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(selection == drink ? recipe.tint.opacity(0.20) : Color.primary.opacity(0.035),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityLabel("选择\(drink.shortTitle)，不记录")
                        .accessibilityAddTraits(selection == drink ? [.isSelected] : [])
                }
            }
            VStack(spacing: 2) {
                HStack {
                    Text("容量").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(selectedML) mL").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                Slider(value: $amount, in: 150...600, step: 150)
                    .tint(recipe.tint).accessibilityLabel("饮用量，每档150毫升")
                    .accessibilityValue("\(selectedML) 毫升")
                HStack(spacing: 0) {
                    ForEach(DrinkAmount.steps, id: \.self) { ml in
                        Button("\(ml)") { amount = Double(ml) }
                            .buttonStyle(.plain).font(.system(size: 10, weight: selectedML == ml ? .bold : .regular))
                            .foregroundStyle(selectedML == ml ? recipe.tint : .secondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("选择 \(ml) 毫升")
                    }
                }
            }
                Button {
                    record()
                } label: {
                    Text("记录\(selection.shortTitle) · \(selectedML) mL").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(recipe.tint)
                    .accessibilityLabel("记录\(selection.shortTitle) \(selectedML) 毫升")
            HStack(spacing: 4) {
                Text(status).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).help(status)
                Spacer(minLength: 0)
                Button("撤销", action: onUndo).font(.system(size: 10)).buttonStyle(.plain)
                    .disabled(progress.lastEntry == nil)
            }
        }
        .padding(compact ? 9 : 11)
        .background(recipe.tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        .onAppear {
            selection = progress.plan.selectedDrink
            amount = Double(DrinkAmount.sliderValue(progress.plan.servingML(for: selection)))
        }
    }
    private var status: String {
        if !feedback.isEmpty { return feedback }
        if let last = progress.lastEntry, let ml = last.amountML { return "上次：\(last.drinkTitle) \(ml) mL" }
        return "滑动或点刻度选择，点击记录"
    }
    private func record() {
        onRecord(selection, selectedML)
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
                HydrationScene(theme: .flowers, fraction: 1, motionEnabled: true, recipe: selected).frame(width: 78, height: 106)
                HydrationScene(theme: .bottle, fraction: 0.8, motionEnabled: true, recipe: selected).frame(width: 58, height: 90)
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
