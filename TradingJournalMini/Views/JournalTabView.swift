import SwiftUI

enum JournalSubTab: String, CaseIterable, Identifiable {
    case trades = "Lệnh"
    case calendar = "Lịch PnL"
    case plan = "Kế hoạch"
    case roadmap = "Roadmap"
    var id: String { rawValue }
}

struct JournalTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var subTab: JournalSubTab = .trades

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Journal", selection: $subTab) {
                    ForEach(JournalSubTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.06, green: 0.08, blue: 0.12))

                switch subTab {
                case .trades:
                    JournalTradesListView()
                case .calendar:
                    JournalCalendarSectionView()
                case .plan:
                    JournalPlansSectionView()
                case .roadmap:
                    JournalRoadmapSectionView()
                }
            }
            .background(Color(red: 0.06, green: 0.08, blue: 0.12))
            .navigationBarHidden(true)
        }
    }
}

// MARK: - 1. Trades List & Lifecycle Inspector

struct JournalTradesListView: View {
    @EnvironmentObject var store: AppStore
    @State private var statusFilter: String = "All"
    @State private var searchText: String = ""
    @State private var selectedTrade: Trade?

    private var currency: String {
        store.selectedAccount?.currency ?? "VND"
    }

    private var filteredTrades: [Trade] {
        store.accountTrades.filter { trade in
            let matchesStatus = statusFilter == "All" || trade.tradeStatus.rawValue == statusFilter
            let matchesSearch = searchText.isEmpty
                || trade.symbolName.localizedCaseInsensitiveContains(searchText)
                || trade.note.localizedCaseInsensitiveContains(searchText)
            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Search & Status Filter
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm mã cổ phiếu, ghi chú...", text: $searchText)
                        .font(.subheadline)
                }
                .padding(10)
                .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Open", "Closed", "ScaleIn", "ScaleOut"], id: \.self) { st in
                            Button {
                                statusFilter = st
                            } label: {
                                Text(st == "All" ? "Tất cả (\(store.accountTrades.count))" : st)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(statusFilter == st ? Color.blue : Color.white.opacity(0.07))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }

                if filteredTrades.isEmpty {
                    Text("Không có giao dịch nào khớp bộ lọc.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 40)
                } else {
                    ForEach(filteredTrades) { trade in
                        let mark = store.symbolPricesMap[trade.symbolName.uppercased()]
                        let lc = TradeCalculator.buildTradeLifecycle(trade, currentPrice: mark, account: store.selectedAccount)
                        let pnl = TradeCalculator.calculateDerivativeTradePnL(trade, currentPrice: mark, account: store.selectedAccount)

                        Button {
                            selectedTrade = trade
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(trade.symbolName)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(trade.type.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((trade.type == .long ? Color.green : Color.red).opacity(0.18))
                                        .foregroundColor(trade.type == .long ? .green : .red)
                                        .clipShape(Capsule())
                                    Text(trade.tradeStatus.labelVN)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.18))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())

                                    if trade.isDirty {
                                        Text("Chưa sync")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundColor(.orange)
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    Text(MoneyFormatter.formatSigned(pnl, currency: currency, compact: true))
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundColor(pnl >= 0 ? .green : .red)
                                }

                                HStack {
                                    Text(trade.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("KL mở: \(MoneyFormatter.formatVolume(lc.summary.openVolume)) · Giá TB: \(MoneyFormatter.formatPrice(lc.summary.avgCost))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if !trade.note.isEmpty {
                                    Text(trade.note)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.75))
                                        .lineLimit(2)
                                }
                            }
                            .padding(14)
                            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .sheet(item: $selectedTrade) { trade in
            TradeDetailInspectorSheet(trade: trade)
                .environmentObject(store)
        }
    }
}

// MARK: - 2. Calendar Heatmap Section (mirrors JournalCalendar.jsx)

struct JournalCalendarSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var currentMonthDate: Date = Date()
    @State private var selectedDayKey: String?

    private var currency: String {
        store.selectedAccount?.currency ?? "VND"
    }

    private let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var tradesByDay: [String: (pnl: Double, trades: [Trade])] {
        var map: [String: (pnl: Double, trades: [Trade])] = [:]
        let prices = store.symbolPricesMap
        for trade in store.accountTrades {
            let key = dayKeyFormatter.string(from: trade.date)
            let pnl = TradeCalculator.calculateDerivativeTradePnL(trade, currentPrice: prices[trade.symbolName.uppercased()], account: store.selectedAccount)
            let cur = map[key] ?? (0.0, [])
            map[key] = (cur.pnl + pnl, cur.trades + [trade])
        }
        return map
    }

    private var monthDays: [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: currentMonthDate),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonthDate)) else {
            return []
        }
        let weekday = cal.component(.weekday, from: firstOfMonth) // 1 = Sun ... 7 = Sat
        let leadingEmpty = (weekday + 5) % 7 // Monday-first
        var result: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                result.append(d)
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Month Switcher
                HStack {
                    Button {
                        currentMonthDate = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthDate) ?? currentMonthDate
                    } label: {
                        Image(systemName: "chevron.left")
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }

                    Spacer()
                    Text(currentMonthDate.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()

                    Button {
                        currentMonthDate = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) ?? currentMonthDate
                    } label: {
                        Image(systemName: "chevron.right")
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 14)

                // Calendar Grid
                VStack(spacing: 8) {
                    let headers = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                        ForEach(headers, id: \.self) { h in
                            Text(h)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }

                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, dateOpt in
                            if let date = dateOpt {
                                let key = dayKeyFormatter.string(from: date)
                                let dayData = tradesByDay[key]
                                let dayNum = Calendar.current.component(.day, from: date)
                                Button {
                                    selectedDayKey = key
                                } label: {
                                    VStack(spacing: 2) {
                                        Text("\(dayNum)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                        if let data = dayData {
                                            Text(MoneyFormatter.format(data.pnl, currency: currency, compact: true))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(data.pnl >= 0 ? .green : .red)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                        } else {
                                            Text(" ")
                                                .font(.system(size: 8))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        dayData == nil ? Color.white.opacity(0.04) :
                                            (dayData!.pnl >= 0 ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedDayKey == key ? Color.blue : Color.clear, lineWidth: 1.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)

                if let key = selectedDayKey, let dayInfo = tradesByDay[key] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Chi tiết ngày \(key)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Text(MoneyFormatter.formatSigned(dayInfo.pnl, currency: currency))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(dayInfo.pnl >= 0 ? .green : .red)
                        }
                        ForEach(dayInfo.trades) { t in
                            HStack {
                                Text(t.symbolName)
                                    .fontWeight(.bold)
                                Text(t.type.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(t.tradeStatus.labelVN)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(14)
                    .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - 3. Daily & Weekly Plan Section (mirrors Plan.jsx)

struct JournalPlansSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var showPlanSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("Kế hoạch Ngày & Tuần")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        showPlanSheet = true
                    } label: {
                        Label("Tạo Plan", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)

                if store.accountPlans.isEmpty {
                    Text("Chưa có kế hoạch giao dịch nào cho tài khoản này.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 40)
                } else {
                    ForEach(store.accountPlans) { plan in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(plan.scope.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.2))
                                    .foregroundColor(.purple)
                                    .clipShape(Capsule())
                                Text(plan.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(plan.status.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                            }

                            if !plan.symbols.isEmpty {
                                Text("Tâm điểm: \(plan.symbols)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            if !plan.marketContext.isEmpty {
                                Text("Bối cảnh: \(plan.marketContext)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !plan.entryPlan.isEmpty {
                                Text("Kịch bản: \(plan.entryPlan)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            HStack {
                                Text("Tối đa: \(plan.maxTrades) lệnh/phiên")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Spacer()
                                Button(role: .destructive) {
                                    store.deletePlan(plan)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 14)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanFormSheet()
                .environmentObject(store)
        }
    }
}

// MARK: - 4. Roadmap Section (mirrors Roadmap.jsx & roadmapCalculations.js)

struct JournalRoadmapSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var growthTargetPct: Double = 25
    @State private var plannedTrades: Int = 25
    @State private var riskPct: Double = 1.0
    @State private var rewardMultiple: Double = 2.0
    @State private var winRateEst: Double = 55.0

    private var account: Account? { store.selectedAccount }
    private var currency: String { account?.currency ?? "VND" }

    private var projection: RoadmapProjection {
        RoadmapCalculator.buildProjection(
            startBalance: account?.initialBalance ?? 100_000_000,
            riskPercent: riskPct,
            targetGrowthPercent: growthTargetPct,
            rewardMultiple: rewardMultiple,
            plannedTrades: plannedTrades,
            winRateEstimate: winRateEst,
            maxDrawDownPercent: account?.setting?.maxDrawDown ?? 10.0
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LỘ TRÌNH TĂNG TRƯỞNG KÉP (ROADMAP)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.blue)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vốn mục tiêu (+\(Int(growthTargetPct))%)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(MoneyFormatter.format(projection.targetBalance, currency: currency, compact: true))
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.green)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Số lệnh thắng cần đạt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(projection.winsNeededInPlannedTrades ?? 0) / \(plannedTrades) lệnh")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    HStack {
                        Stepper("Mục tiêu: +\(Int(growthTargetPct))%", value: $growthTargetPct, in: 5...200, step: 5)
                            .font(.caption)
                    }
                    HStack {
                        Stepper("Số lệnh: \(plannedTrades)", value: $plannedTrades, in: 5...100, step: 5)
                            .font(.caption)
                    }
                    HStack {
                        Stepper(String(format: "R:R Mục tiêu: 1 : %.1f", rewardMultiple), value: $rewardMultiple, in: 1.0...5.0, step: 0.2)
                            .font(.caption)
                    }
                }
                .padding(14)
                .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)

                // Step-by-step Compound Table
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bảng Lãi Kép Theo Chuỗi Thắng")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    ForEach(projection.rows.prefix(12)) { row in
                        HStack {
                            Text("#\(row.tradeNumber)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Text(MoneyFormatter.format(row.winEquity, currency: currency, compact: true))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Text("+\(MoneyFormatter.format(row.winProfit, currency: currency, compact: true))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                        Divider().background(Color.white.opacity(0.05))
                    }
                }
                .padding(14)
                .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 24)
        }
    }
}

