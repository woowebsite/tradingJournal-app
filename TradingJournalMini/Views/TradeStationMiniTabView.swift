import SwiftUI

enum StationMiniSegment: String, CaseIterable, Identifiable {
    case todayTrades = "Today Trades"
    case todayPortfolio = "Today Portfolio"
    case calcVol = "Tính KL & R:R"
    var id: String { rawValue }
}

struct TradeStationMiniTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var segment: StationMiniSegment = .todayTrades
    @State private var selectedTradeForDetail: Trade?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Chế độ", selection: $segment) {
                        ForEach(StationMiniSegment.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    switch segment {
                    case .todayTrades:
                        TodayTradesSectionView(selectedTrade: $selectedTradeForDetail)
                    case .todayPortfolio:
                        TodayPortfolioSectionView()
                    case .calcVol:
                        CalcVolumeMiniView()
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.06, green: 0.08, blue: 0.12))
            .navigationBarHidden(true)
            .sheet(item: $selectedTradeForDetail) { trade in
                TradeDetailInspectorSheet(trade: trade)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - 1. Today Trades Section (mirrors TodayTrades.jsx)

struct TodayTradesSectionView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTrade: Trade?

    private var currency: String {
        store.selectedAccount?.currency ?? "VND"
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private var enrichedTodayTrades: [(trade: Trade, isAddOnOnly: Bool, todayAddOnCount: Int, currentPrice: Double?, derivedPnl: Double)] {
        let prices = store.symbolPricesMap
        return store.todayTrades.map { trade in
            let sorted = trade.tradeDetails.filter { !$0.isDeleted }.sorted { $0.date < $1.date }
            let firstEntry = sorted.first(where: { $0.signal == .entry }) ?? sorted.first
            let isAddOnOnly = !isToday(trade.date)
            let todayAddOns = sorted.filter { $0.signal == .entry && $0.documentId != firstEntry?.documentId && isToday($0.date) }
            let curPrice = prices[trade.symbolName.uppercased()]

            var tradeForPnl = trade
            if isAddOnOnly && !todayAddOns.isEmpty {
                tradeForPnl.tradeDetails = todayAddOns
            }
            let pnl = TradeCalculator.calculateDerivativeTradePnL(tradeForPnl, currentPrice: curPrice, account: store.selectedAccount)
            return (trade, isAddOnOnly, todayAddOns.count, curPrice, pnl)
        }
    }

    private var totalTodayPnl: Double {
        enrichedTodayTrades.reduce(0.0) { $0 + $1.derivedPnl }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header Summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lệnh Mở & Nhồi Hôm Nay")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Tổng PnL Hôm Nay")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(MoneyFormatter.formatSigned(totalTodayPnl, currency: currency))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(totalTodayPnl >= 0 ? .green : .red)
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            if enrichedTodayTrades.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Không có lệnh mở mới hoặc nhồi lệnh trong hôm nay.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)
            } else {
                ForEach(enrichedTodayTrades, id: \.trade.documentId) { item in
                    Button {
                        selectedTrade = item.trade
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(item.trade.type == .long ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(item.trade.symbolName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text(item.trade.type.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((item.trade.type == .long ? Color.green : Color.red).opacity(0.18))
                                    .foregroundColor(item.trade.type == .long ? .green : .red)
                                    .clipShape(Capsule())

                                if item.todayAddOnCount > 0 {
                                    Text("+\(item.todayAddOnCount) add-on hôm nay")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.isAddOnOnly ? "Add-on PnL" : "PnL")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(MoneyFormatter.formatSigned(item.derivedPnl, currency: currency))
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(item.derivedPnl >= 0 ? .green : .red)
                                }
                            }

                            // Execution chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(item.trade.tradeDetails.filter { !$0.isDeleted }) { d in
                                        HStack(spacing: 4) {
                                            Text(d.signal.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.blue)
                                            Text(MoneyFormatter.formatPrice(d.price))
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.white)
                                            Text("×\(MoneyFormatter.formatVolume(d.volume))")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
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
    }
}

// MARK: - 2. Today Portfolio Section (mirrors TodayPortfolio.jsx & todayPortfolio.js)

struct PortfolioHoldingRow: Identifiable {
    var id: String { symbolName }
    var symbolName: String
    var openVolume: Double
    var avgCost: Double
    var markPrice: Double
    var prevClose: Double?
    var changePct: Double?
    var marketValue: Double
    var unrealizedPnl: Double
    var unrealizedPct: Double
}

struct TodayPortfolioSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingSymbol: String?
    @State private var priceInput: String = ""

    private var currency: String {
        store.selectedAccount?.currency ?? "VND"
    }

    private var holdings: [PortfolioHoldingRow] {
        let acc = store.selectedAccount
        let symMap = Dictionary(uniqueKeysWithValues: store.symbols.map { ($0.name.uppercased(), $0) })
        var bySymbol: [String: (vol: Double, costVal: Double, ptVal: Double)] = [:]

        for trade in store.accountOpenTrades {
            let sym = trade.symbolName.uppercased()
            let mark = symMap[sym]?.lastClose
            let lc = TradeCalculator.buildTradeLifecycle(trade, currentPrice: mark, account: acc)
            guard lc.summary.openVolume > 0 else { continue }
            let ptVal = MarketClassifier.pointValue(for: trade, account: acc)
            let cur = bySymbol[sym] ?? (0, 0, ptVal)
            bySymbol[sym] = (
                cur.vol + lc.summary.openVolume,
                cur.costVal + (lc.summary.openVolume * lc.summary.avgCost),
                ptVal
            )
        }

        return bySymbol.keys.sorted().compactMap { sym in
            guard let item = bySymbol[sym], item.vol > 0 else { return nil }
            let avgCost = item.costVal / item.vol
            let symObj = symMap[sym]
            let mark = symObj?.lastClose ?? avgCost
            let mktVal = item.vol * mark * item.ptVal
            let costBasis = item.vol * avgCost * item.ptVal
            let uPnl = mktVal - costBasis
            let uPct = costBasis > 0 ? (uPnl / costBasis) * 100.0 : 0.0
            return PortfolioHoldingRow(
                symbolName: sym,
                openVolume: item.vol,
                avgCost: avgCost,
                markPrice: mark,
                prevClose: symObj?.prevClose,
                changePct: symObj?.changePct,
                marketValue: mktVal,
                unrealizedPnl: uPnl,
                unrealizedPct: uPct
            )
        }
    }

    private var totalUnrealized: Double {
        holdings.reduce(0.0) { $0 + $1.unrealizedPnl }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Summary Card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Danh mục Vị thế đang nắm giữ")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(holdings.count) mã đang mở · Chạm vào giá để cập nhật Giá khớp")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Tạm tính")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(MoneyFormatter.formatSigned(totalUnrealized, currency: currency, compact: true))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(totalUnrealized >= 0 ? .green : .red)
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            if holdings.isEmpty {
                Text("Danh mục hiện không có vị thế mở.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
            } else {
                ForEach(holdings) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(row.symbolName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            if let chg = row.changePct {
                                Text(String(format: "%@%.2f%% phiên", chg >= 0 ? "+" : "", chg))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((chg >= 0 ? Color.green : Color.red).opacity(0.18))
                                    .foregroundColor(chg >= 0 ? .green : .red)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Button {
                                editingSymbol = row.symbolName
                                priceInput = String(row.markPrice)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Giá TT: \(MoneyFormatter.formatPrice(row.markPrice))")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    Image(systemName: "pencil.line")
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                            }
                        }

                        Divider().background(Color.white.opacity(0.08))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Khối lượng mở")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(MoneyFormatter.formatVolume(row.openVolume))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Giá vốn TB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(MoneyFormatter.formatPrice(row.avgCost))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Lãi/Lỗ Tạm tính")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(MoneyFormatter.formatSigned(row.unrealizedPnl, currency: currency, compact: true)) (\(String(format: "%@%.1f%%", row.unrealizedPct >= 0 ? "+" : "", row.unrealizedPct)))")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(row.unrealizedPnl >= 0 ? .green : .red)
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
        .alert("Cập nhật Giá thị trường (\(editingSymbol ?? ""))", isPresented: Binding(
            get: { editingSymbol != nil },
            set: { if !$0 { editingSymbol = nil } }
        )) {
            TextField("Giá hiện tại", text: $priceInput)
                .keyboardType(.decimalPad)
            Button("Hủy", role: .cancel) { editingSymbol = nil }
            Button("Lưu") {
                if let sym = editingSymbol, let val = Double(priceInput.replacingOccurrences(of: ",", with: ".")), val > 0 {
                    store.updateSymbolPrice(symbolName: sym, newClose: val)
                }
                editingSymbol = nil
            }
        }
    }
}

// MARK: - 3. Calc Volume & R:R Calculator (mirrors CalcVolForm.jsx)

struct CalcVolumeMiniView: View {
    @EnvironmentObject var store: AppStore
    @State private var symbolText: String = "FPT"
    @State private var entryPriceText: String = "138500"
    @State private var slPriceText: String = "134000"
    @State private var tpPriceText: String = "148500"
    @State private var customRiskAmountText: String = ""
    @State private var createdBanner: Bool = false

    private var account: Account? { store.selectedAccount }
    private var currency: String { account?.currency ?? "VND" }

    private var defaultRiskAmount: Double {
        guard let acc = account else { return 0 }
        let riskPct = acc.setting?.riskPerTrade ?? 1.0
        return acc.initialBalance * (riskPct / 100.0)
    }

    private var effectiveRiskAmount: Double {
        if let manual = Double(customRiskAmountText.replacingOccurrences(of: ",", with: "")), manual > 0 {
            return manual
        }
        return defaultRiskAmount
    }

    private var entryPrice: Double { Double(entryPriceText.replacingOccurrences(of: ",", with: "")) ?? 0 }
    private var slPrice: Double { Double(slPriceText.replacingOccurrences(of: ",", with: "")) ?? 0 }
    private var tpPrice: Double { Double(tpPriceText.replacingOccurrences(of: ",", with: "")) ?? 0 }

    private var pointValue: Double {
        MarketClassifier.isDerivativeContext(account: account, symbolName: symbolText) ? MarketClassifier.vnDerivativePointValue : 1.0
    }

    private var stopDistance: Double {
        (entryPrice > 0 && slPrice > 0) ? abs(entryPrice - slPrice) : 0
    }

    private var rewardDistance: Double {
        (entryPrice > 0 && tpPrice > 0) ? abs(tpPrice - entryPrice) : 0
    }

    private var recommendedVolume: Double {
        guard stopDistance > 0, effectiveRiskAmount > 0 else { return 0 }
        let rawVol = effectiveRiskAmount / (stopDistance * pointValue)
        if pointValue > 1 {
            return floor(rawVol)
        }
        return (rawVol * 100).rounded() / 100
    }

    private var positionCapitalValue: Double {
        recommendedVolume * entryPrice * pointValue
    }

    private var projectedProfit: Double {
        recommendedVolume * rewardDistance * pointValue
    }

    private var rrRatio: Double {
        stopDistance > 0 ? (rewardDistance / stopDistance) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TÍNH KHỐI LƯỢNG VỊ THẾ (CALC VOLUME)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                Text("Tự động tính khối lượng tối ưu từ % Rủi ro tài khoản, Giá vào và Điểm dừng lỗ (SL).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mã giao dịch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("VD: FPT, VN30F1M", text: $symbolText)
                            .textInputAutocapitalization(.characters)
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Giá vào (Entry)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0.0", text: $entryPriceText)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Giá cắt lỗ (SL)")
                            .font(.caption)
                            .foregroundColor(.red)
                        TextField("Stop Loss", text: $slPriceText)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Giá chốt lời (TP)")
                            .font(.caption)
                            .foregroundColor(.green)
                        TextField("Take Profit", text: $tpPriceText)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Số tiền chấp nhận rủi ro (Risk Amount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Mặc định: \(String(format: "%.1f%%", account?.setting?.riskPerTrade ?? 1.0)) = \(MoneyFormatter.format(defaultRiskAmount, currency: currency, compact: true))")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    TextField(String(format: "%.0f", defaultRiskAmount), text: $customRiskAmountText)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            // Calculated Output Box
            VStack(spacing: 12) {
                HStack {
                    Text("Khối lượng khuyến nghị")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(MoneyFormatter.formatVolume(recommendedVolume))
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundColor(.blue)
                }

                Divider().background(Color.white.opacity(0.1))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Giá trị vị thế")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(MoneyFormatter.format(positionCapitalValue, currency: currency, compact: true))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 4) {
                        Text("Tỷ lệ R:R")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "1 : %.2f", rrRatio))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(rrRatio >= 2.0 ? .green : .orange)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Lợi nhuận mục tiêu")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("+\(MoneyFormatter.format(projectedProfit, currency: currency, compact: true))")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                Button {
                    createTradeFromCalc()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Mở lệnh ngay với khối lượng này")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(recommendedVolume > 0 ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(recommendedVolume <= 0)

                if createdBanner {
                    Text("Đã tạo lệnh \(symbolText.uppercased()) vào Nhật ký giao dịch!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
        }
    }

    private func createTradeFromCalc() {
        guard let acc = account, recommendedVolume > 0, entryPrice > 0 else { return }
        let isLong = slPrice == 0 || entryPrice >= slPrice
        let tradeId = "trd_\(UUID().uuidString.lowercased().prefix(12))"
        let detail = TradeDetail(
            documentId: "td_\(UUID().uuidString.lowercased().prefix(12))",
            rawId: nil,
            tradeDocumentId: tradeId,
            price: entryPrice,
            type: isLong ? .buy : .sell,
            volume: recommendedVolume,
            signal: .entry,
            date: Date(),
            note: String(format: "SL: %@ | TP: %@ | R:R 1:%.2f", MoneyFormatter.formatPrice(slPrice), MoneyFormatter.formatPrice(tpPrice), rrRatio),
            createdAt: Date(),
            updatedAt: Date(),
            isDirty: true,
            isDeleted: false
        )
        let newTrade = Trade(
            documentId: tradeId,
            rawId: nil,
            type: isLong ? .long : .short,
            tradeStatus: .open,
            note: "Mở từ Calc Volume trên iPhone (SL: \(MoneyFormatter.formatPrice(slPrice)), TP: \(MoneyFormatter.formatPrice(tpPrice)))",
            date: Date(),
            accountDocumentId: acc.documentId,
            symbolDocumentId: nil,
            symbolName: symbolText.uppercased(),
            strategyDocumentId: acc.strategyDocumentId,
            strategyName: acc.strategyName,
            scored: 8,
            pnl: nil,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: [detail],
            createdAt: Date(),
            updatedAt: Date(),
            isDirty: true,
            isDeleted: false
        )
        store.saveTrade(newTrade)
        createdBanner = true
    }
}

