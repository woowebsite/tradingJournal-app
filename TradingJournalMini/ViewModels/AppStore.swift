import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var selectedAccountId: String = "" {
        didSet {
            UserDefaults.standard.set(selectedAccountId, forKey: "tj_selected_account_id")
        }
    }
    @Published var symbols: [SymbolItem] = []
    @Published var strategies: [StrategyItem] = []
    @Published var trades: [Trade] = []
    @Published var plans: [TradingPlan] = []
    @Published var roadmaps: [RoadmapItem] = []
    @Published var lastSyncDate: Date?
    @Published var bannerMessage: String?

    private let db = SQLiteDatabase.shared
    private let syncManager = SyncSnapshotManager.shared

    init() {
        reloadFromDatabase()
        if accounts.isEmpty {
            seedDemoData()
            reloadFromDatabase()
        }
        let savedAccId = UserDefaults.standard.string(forKey: "tj_selected_account_id") ?? ""
        if accounts.contains(where: { $0.documentId == savedAccId }) {
            selectedAccountId = savedAccId
        } else if let first = accounts.first {
            selectedAccountId = first.documentId
        }
    }

    func reloadFromDatabase() {
        accounts = db.fetchAccounts()
        symbols = db.fetchSymbols()
        strategies = db.fetchStrategies()
        trades = db.fetchTrades(includeDeleted: false)
        plans = db.fetchPlans(includeDeleted: false)
        roadmaps = db.fetchRoadmaps(includeDeleted: false)
    }

    var selectedAccount: Account? {
        accounts.first(where: { $0.documentId == selectedAccountId }) ?? accounts.first
    }

    var symbolPricesMap: [String: Double] {
        var map: [String: Double] = [:]
        for sym in symbols {
            if let close = sym.lastClose, close > 0 {
                map[sym.name.uppercased()] = close
            }
        }
        return map
    }

    var accountTrades: [Trade] {
        guard let acc = selectedAccount else { return trades }
        return trades.filter { $0.accountDocumentId == acc.documentId && !$0.isDeleted }
    }

    var accountOpenTrades: [Trade] {
        accountTrades.filter { $0.tradeStatus != .closed }
    }

    var todayTrades: [Trade] {
        let cal = Calendar.current
        return accountOpenTrades.filter { trade in
            if cal.isDateInToday(trade.date) { return true }
            return trade.tradeDetails.contains { !$0.isDeleted && $0.signal == .entry && cal.isDateInToday($0.date) }
        }
    }

    var accountPlans: [TradingPlan] {
        guard let acc = selectedAccount else { return plans }
        return plans.filter { $0.accountId == acc.documentId && !$0.isDeleted }
    }

    var accountRoadmaps: [RoadmapItem] {
        guard let acc = selectedAccount else { return roadmaps }
        return roadmaps.filter { $0.accountDocumentId == acc.documentId && !$0.isDeleted }
    }

    var dirtyChangesCount: Int {
        let dirtyTrades = trades.filter(\.isDirty).count
        let dirtyPlans = plans.filter(\.isDirty).count
        let dirtyRoadmaps = roadmaps.filter(\.isDirty).count
        let dirtyAccounts = accounts.filter(\.isDirty).count
        return dirtyTrades + dirtyPlans + dirtyRoadmaps + dirtyAccounts
    }

    // MARK: - Symbol Price Update (for Today Portfolio / Station)

    func updateSymbolPrice(symbolName: String, newClose: Double, prevClose: Double? = nil) {
        let upper = symbolName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty, newClose > 0 else { return }

        if var existing = symbols.first(where: { $0.name.uppercased() == upper }) {
            if let prev = prevClose, prev > 0 {
                existing.prevClose = prev
            } else if existing.prevClose == nil {
                existing.prevClose = existing.lastClose ?? newClose
            }
            existing.lastClose = newClose
            existing.updatedAt = Date()
            existing.isDirty = true
            db.saveSymbol(existing)
        } else {
            let created = SymbolItem(
                documentId: "sym_\(upper.lowercased())",
                rawId: nil,
                name: upper,
                description: upper,
                exchange: nil,
                shortName: upper,
                industry: nil,
                sector: nil,
                marketDocumentId: selectedAccount?.marketDocumentId,
                lastClose: newClose,
                prevClose: prevClose ?? newClose,
                lastVolume: nil,
                avgVolume20d: nil,
                ma20: nil,
                lastPriceDate: ISO8601DateFormatter().string(from: Date()),
                updatedAt: Date(),
                isDirty: true
            )
            db.saveSymbol(created)
        }
        reloadFromDatabase()
    }

    // MARK: - Trade CRUD

    func saveTrade(_ trade: Trade) {
        var updated = trade
        updated.symbolName = trade.symbolName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        updated.updatedAt = Date()
        updated.isDirty = true

        // Recalculate saved pnl in price units (matching Desktop tradeCalculations.js)
        let markPrice = symbolPricesMap[updated.symbolName]
        updated.pnl = TradeCalculator.calculateTradePnL(updated, currentPrice: markPrice)

        // Ensure symbol exists in catalog
        if !symbols.contains(where: { $0.name.uppercased() == updated.symbolName }) {
            let firstPrice = updated.tradeDetails.first?.price
            let newSym = SymbolItem(
                documentId: updated.symbolDocumentId ?? "sym_\(updated.symbolName.lowercased())",
                rawId: nil,
                name: updated.symbolName,
                description: updated.symbolName,
                exchange: nil,
                shortName: updated.symbolName,
                industry: nil,
                sector: nil,
                marketDocumentId: selectedAccount?.marketDocumentId,
                lastClose: firstPrice,
                prevClose: firstPrice,
                lastVolume: nil,
                avgVolume20d: nil,
                ma20: nil,
                lastPriceDate: nil,
                updatedAt: Date(),
                isDirty: true
            )
            db.saveSymbol(newSym)
        }

        db.saveTrade(updated)
        reloadFromDatabase()
    }

    func addExecutionDetail(to trade: Trade, side: OrderSide, signal: TradeSignalType, price: Double, volume: Double, date: Date = Date(), note: String = "", autoCloseIfFlat: Bool = true) {
        var updated = trade
        let detail = TradeDetail(
            documentId: "td_\(UUID().uuidString.lowercased().prefix(12))",
            rawId: nil,
            tradeDocumentId: trade.documentId,
            price: price,
            type: side,
            volume: volume,
            signal: signal,
            date: date,
            note: note,
            createdAt: Date(),
            updatedAt: Date(),
            isDirty: true,
            isDeleted: false
        )
        updated.tradeDetails.append(detail)

        let lifecycle = TradeCalculator.buildTradeLifecycle(updated, currentPrice: price, account: selectedAccount)
        if autoCloseIfFlat && lifecycle.summary.isFlat {
            updated.tradeStatus = .closed
        } else if signal == .entry && updated.tradeDetails.filter({ $0.signal == .entry }).count > 1 {
            updated.tradeStatus = .scaleIn
        } else if (signal == .takeProfit || signal == .exit || signal == .stoploss) && lifecycle.summary.openVolume > 0 {
            updated.tradeStatus = .scaleOut
        }

        saveTrade(updated)
    }

    func deleteTrade(_ trade: Trade) {
        var updated = trade
        updated.isDeleted = true
        updated.isDirty = true
        updated.updatedAt = Date()
        db.saveTrade(updated)
        reloadFromDatabase()
    }

    // MARK: - Plan CRUD

    func savePlan(_ plan: TradingPlan) {
        var updated = plan
        updated.updatedAt = Date()
        updated.isDirty = true
        db.savePlan(updated)
        reloadFromDatabase()
    }

    func deletePlan(_ plan: TradingPlan) {
        var updated = plan
        updated.isDeleted = true
        updated.isDirty = true
        updated.updatedAt = Date()
        db.savePlan(updated)
        reloadFromDatabase()
    }

    // MARK: - Roadmap CRUD

    func saveRoadmap(_ roadmap: RoadmapItem) {
        var updated = roadmap
        updated.updatedAt = Date()
        updated.isDirty = true
        db.saveRoadmap(updated)
        reloadFromDatabase()
    }

    func deleteRoadmap(_ roadmap: RoadmapItem) {
        var updated = roadmap
        updated.isDeleted = true
        updated.isDirty = true
        updated.updatedAt = Date()
        db.saveRoadmap(updated)
        reloadFromDatabase()
    }

    // MARK: - Account Setting Update

    func updateAccountRiskSetting(account: Account, riskPerTrade: Double, maxDrawDown: Double, capitalRisk: Double, timeframe: String) {
        var updatedAccount = account
        updatedAccount.timeframe = timeframe
        updatedAccount.updatedAt = Date()
        updatedAccount.isDirty = true

        var setting = account.setting ?? RiskSetting(
            documentId: account.settingDocumentId ?? "set_\(account.documentId)",
            rawId: nil,
            name: "\(account.name) Risk",
            riskPerTrade: riskPerTrade,
            maxDrawDown: maxDrawDown,
            capitalRisk: capitalRisk,
            accountDocumentId: account.documentId,
            updatedAt: Date(),
            isDirty: true
        )
        setting.riskPerTrade = riskPerTrade
        setting.maxDrawDown = maxDrawDown
        setting.capitalRisk = capitalRisk
        setting.updatedAt = Date()
        setting.isDirty = true

        updatedAccount.setting = setting
        updatedAccount.settingDocumentId = setting.documentId
        db.saveAccount(updatedAccount)
        reloadFromDatabase()
    }

    // MARK: - Sync Snapshot Export / Import

    func exportSyncSnapshotData() throws -> Data {
        try syncManager.exportSnapshotData()
    }

    func importSyncSnapshotData(_ data: Data, mode: SyncImportMode) throws -> SyncImportSummary {
        let summary = try syncManager.importSnapshotData(data, mode: mode)
        lastSyncDate = Date()
        reloadFromDatabase()
        if !accounts.contains(where: { $0.documentId == selectedAccountId }), let first = accounts.first {
            selectedAccountId = first.documentId
        }
        return summary
    }

    func markLocalChangesSynced() {
        db.markAllSynced()
        lastSyncDate = Date()
        reloadFromDatabase()
    }

    // MARK: - Demo Seed Data (Realistic VNStock, VN30F1M Derivative & Crypto)

    func seedDemoData() {
        let now = Date()
        let cal = Calendar.current

        // Strategies
        let stratBreakout = StrategyItem(
            documentId: "strat_vcp_breakout",
            rawId: 1,
            name: "VCP Breakout + Volume Spike",
            description: "Mua nền giá thu hẹp VCP vượt đỉnh kèm khối lượng > 1.5x MA20",
            type: "Rules",
            strategyFile: nil,
            template: "VCP",
            updatedAt: now
        )
        let stratTrendFollow = StrategyItem(
            documentId: "strat_vn30f_trend",
            rawId: 2,
            name: "VN30F1M Intraday VWAP + EMA20",
            description: "Thuận xu hướng VWAP phiên sáng và cấu trúc đỉnh đáy M5",
            type: "Python",
            strategyFile: "vn30f_vwap.py",
            template: "Intraday",
            updatedAt: now
        )
        db.saveStrategy(stratBreakout)
        db.saveStrategy(stratTrendFollow)

        // Risk Settings
        let setVN = RiskSetting(
            documentId: "set_vn_equity",
            rawId: 1,
            name: "VNStock Growth Risk",
            riskPerTrade: 1.0,
            maxDrawDown: 8.0,
            capitalRisk: 15.0,
            accountDocumentId: "acc_vn_equity",
            updatedAt: now
        )
        let setDeriv = RiskSetting(
            documentId: "set_vn_deriv",
            rawId: 2,
            name: "VN30F1M Derivative Risk",
            riskPerTrade: 1.2,
            maxDrawDown: 10.0,
            capitalRisk: 12.0,
            accountDocumentId: "acc_vn_deriv",
            updatedAt: now
        )
        let setCrypto = RiskSetting(
            documentId: "set_crypto_usdt",
            rawId: 3,
            name: "Binance Swing Risk",
            riskPerTrade: 1.0,
            maxDrawDown: 12.0,
            capitalRisk: 10.0,
            accountDocumentId: "acc_crypto_usdt",
            updatedAt: now
        )

        // Accounts
        let accVN = Account(
            documentId: "acc_vn_equity",
            rawId: 1,
            name: "TCBS Cơ Sở Tăng Trưởng",
            description: "Danh mục cổ phiếu tăng trưởng HOSE/HNX",
            initialBalance: 500_000_000,
            cash: 220_000_000,
            margin: 0,
            currency: "VND",
            marketDocumentId: "mkt_vnstock",
            marketName: "VNStock",
            settingDocumentId: setVN.documentId,
            setting: setVN,
            strategyDocumentId: stratBreakout.documentId,
            strategyName: stratBreakout.name,
            volumeFormat: "0,0",
            moneyFormat: "0,0",
            feeRate: 0.15,
            sellTaxRate: 0.10,
            feePerContract: 0,
            maxPositionPct: 25,
            maxAverageDown: 1,
            timeframe: "D1",
            allocationJson: "{\"targetPct\": 60}",
            updatedAt: now
        )

        let accDeriv = Account(
            documentId: "acc_vn_deriv",
            rawId: 2,
            name: "TCBS Phái Sinh VN30F1M",
            description: "Giao dịch hợp đồng tương lai chỉ số VN30",
            initialBalance: 150_000_000,
            cash: 150_000_000,
            margin: 35_000_000,
            currency: "VND",
            marketDocumentId: "mkt_derivative",
            marketName: "Derivative",
            settingDocumentId: setDeriv.documentId,
            setting: setDeriv,
            strategyDocumentId: stratTrendFollow.documentId,
            strategyName: stratTrendFollow.name,
            volumeFormat: "0",
            moneyFormat: "0,0",
            feeRate: 0,
            sellTaxRate: 0,
            feePerContract: 20_000,
            maxPositionPct: 50,
            maxAverageDown: 0,
            timeframe: "M15",
            allocationJson: "{\"targetPct\": 20}",
            updatedAt: now
        )

        let accCrypto = Account(
            documentId: "acc_crypto_usdt",
            rawId: 3,
            name: "Binance Crypto Swing",
            description: "Tài khoản Crypto USDT",
            initialBalance: 10_000,
            cash: 6_500,
            margin: 0,
            currency: "USD",
            marketDocumentId: "mkt_crypto",
            marketName: "Crypto",
            settingDocumentId: setCrypto.documentId,
            setting: setCrypto,
            strategyDocumentId: stratBreakout.documentId,
            strategyName: stratBreakout.name,
            volumeFormat: "0.000",
            moneyFormat: "0,0.00",
            feeRate: 0.1,
            sellTaxRate: 0,
            feePerContract: 0,
            maxPositionPct: 30,
            maxAverageDown: 1,
            timeframe: "H4",
            allocationJson: "{\"targetPct\": 20}",
            updatedAt: now
        )

        db.saveAccount(accVN)
        db.saveAccount(accDeriv)
        db.saveAccount(accCrypto)

        // Symbols with latest session moves
        let sampleSymbols: [SymbolItem] = [
            SymbolItem(documentId: "sym_fpt", rawId: 1, name: "FPT", description: "FPT Corp", exchange: "HOSE", shortName: "FPT", industry: "Công nghệ", sector: "Technology", marketDocumentId: "mkt_vnstock", lastClose: 138_500, prevClose: 134_200, lastVolume: 6_800_000, avgVolume20d: 4_100_000, ma20: 133_000, lastPriceDate: "2026-11-03", updatedAt: now),
            SymbolItem(documentId: "sym_ssi", rawId: 2, name: "SSI", description: "Chứng khoán SSI", exchange: "HOSE", shortName: "SSI", industry: "Chứng khoán", sector: "Financials", marketDocumentId: "mkt_vnstock", lastClose: 28_650, prevClose: 28_100, lastVolume: 18_500_000, avgVolume20d: 14_200_000, ma20: 27_900, lastPriceDate: "2026-11-03", updatedAt: now),
            SymbolItem(documentId: "sym_hpg", rawId: 3, name: "HPG", description: "Tập đoàn Hòa Phát", exchange: "HOSE", shortName: "HPG", industry: "Thép", sector: "Materials", marketDocumentId: "mkt_vnstock", lastClose: 27_400, prevClose: 27_600, lastVolume: 21_000_000, avgVolume20d: 19_500_000, ma20: 27_100, lastPriceDate: "2026-11-03", updatedAt: now),
            SymbolItem(documentId: "sym_mwg", rawId: 4, name: "MWG", description: "Thế Giới Di Động", exchange: "HOSE", shortName: "MWG", industry: "Bán lẻ", sector: "Consumer", marketDocumentId: "mkt_vnstock", lastClose: 68_200, prevClose: 66_000, lastVolume: 9_200_000, avgVolume20d: 5_800_000, ma20: 65_400, lastPriceDate: "2026-11-03", updatedAt: now),
            SymbolItem(documentId: "sym_vn30f1m", rawId: 5, name: "VN30F1M", description: "HĐTL Chỉ số VN30", exchange: "HNX", shortName: "VN30F1M", industry: "Phái sinh", sector: "Derivatives", marketDocumentId: "mkt_derivative", lastClose: 1_348.5, prevClose: 1_339.0, lastVolume: 185_000, avgVolume20d: 165_000, ma20: 1_335.0, lastPriceDate: "2026-11-03", updatedAt: now),
            SymbolItem(documentId: "sym_btcusdt", rawId: 6, name: "BTCUSDT", description: "Bitcoin / Tether", exchange: "BINANCE", shortName: "BTC", industry: "Crypto", sector: "Crypto", marketDocumentId: "mkt_crypto", lastClose: 89_400, prevClose: 87_800, lastVolume: 42_000, avgVolume20d: 35_000, ma20: 85_200, lastPriceDate: "2026-11-03", updatedAt: now)
        ]
        sampleSymbols.forEach { db.saveSymbol($0) }

        // Sample Trades for VNStock Account
        let d12 = cal.date(byAdding: .day, value: -12, to: now) ?? now
        let d9 = cal.date(byAdding: .day, value: -9, to: now) ?? now
        let d6 = cal.date(byAdding: .day, value: -6, to: now) ?? now
        let d3 = cal.date(byAdding: .day, value: -3, to: now) ?? now
        let d1 = cal.date(byAdding: .day, value: -1, to: now) ?? now

        let t1 = Trade(
            documentId: "trd_fpt_open_today",
            rawId: 101,
            type: .long,
            tradeStatus: .scaleIn,
            note: "Mua nền VCP FPT tại 131.5k, hôm nay nhồi thêm 500 cổ khi vượt 136k kèm vol lớn.",
            date: d3,
            accountDocumentId: accVN.documentId,
            symbolDocumentId: "sym_fpt",
            symbolName: "FPT",
            strategyDocumentId: stratBreakout.documentId,
            strategyName: stratBreakout.name,
            scored: 9,
            pnl: nil,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: [
                TradeDetail(documentId: "td_fpt_1", rawId: 1, tradeDocumentId: "trd_fpt_open_today", price: 131_500, type: .buy, volume: 1_000, signal: .entry, date: d3, note: "Vị thế thăm dò tại nền chặt", createdAt: d3, updatedAt: d3),
                TradeDetail(documentId: "td_fpt_2", rawId: 2, tradeDocumentId: "trd_fpt_open_today", price: 136_000, type: .buy, volume: 500, signal: .entry, date: now, note: "Gia tăng tỷ trọng (Pyramid) phiên hôm nay", createdAt: now, updatedAt: now)
            ],
            createdAt: d3,
            updatedAt: now
        )

        let t2 = Trade(
            documentId: "trd_mwg_today",
            rawId: 102,
            type: .long,
            tradeStatus: .open,
            note: "Điểm mua Pocket Pivot MWG vượt MA20 ngay phiên sáng hôm nay.",
            date: now,
            accountDocumentId: accVN.documentId,
            symbolDocumentId: "sym_mwg",
            symbolName: "MWG",
            strategyDocumentId: stratBreakout.documentId,
            strategyName: stratBreakout.name,
            scored: 8,
            pnl: nil,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: [
                TradeDetail(documentId: "td_mwg_1", rawId: 3, tradeDocumentId: "trd_mwg_today", price: 66_500, type: .buy, volume: 2_000, signal: .entry, date: now, note: "Khớp lệnh phiên sáng", createdAt: now, updatedAt: now)
            ],
            createdAt: now,
            updatedAt: now
        )

        let t3 = Trade(
            documentId: "trd_ssi_closed",
            rawId: 103,
            type: .long,
            tradeStatus: .closed,
            note: "Chốt lời chủ động SSI khi chạm kháng cự kênh trên (+8.2%).",
            date: d12,
            accountDocumentId: accVN.documentId,
            symbolDocumentId: "sym_ssi",
            symbolName: "SSI",
            strategyDocumentId: stratBreakout.documentId,
            strategyName: stratBreakout.name,
            scored: 9,
            pnl: 11_000_000,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: [
                TradeDetail(documentId: "td_ssi_1", rawId: 4, tradeDocumentId: "trd_ssi_closed", price: 26_400, type: .buy, volume: 5_000, signal: .entry, date: d12, note: "Mua tại hỗ trợ MA50", createdAt: d12, updatedAt: d12),
                TradeDetail(documentId: "td_ssi_2", rawId: 5, tradeDocumentId: "trd_ssi_closed", price: 28_600, type: .sell, volume: 5_000, signal: .takeProfit, date: d6, note: "Chốt lời toàn bộ tại mục tiêu 2R", createdAt: d6, updatedAt: d6)
            ],
            createdAt: d12,
            updatedAt: d6
        )

        let t4 = Trade(
            documentId: "trd_hpg_closed_sl",
            rawId: 104,
            type: .long,
            tradeStatus: .closed,
            note: "Cắt lỗ kỷ luật HPG khi gãy nền ngắn hạn (-2.8%).",
            date: d9,
            accountDocumentId: accVN.documentId,
            symbolDocumentId: "sym_hpg",
            symbolName: "HPG",
            strategyDocumentId: stratBreakout.documentId,
            strategyName: stratBreakout.name,
            scored: 7,
            pnl: -3_200_000,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: [
                TradeDetail(documentId: "td_hpg_1", rawId: 6, tradeDocumentId: "trd_hpg_closed_sl", price: 28_000, type: .buy, volume: 4_000, signal: .entry, date: d9, note: "Mua breakout giả", createdAt: d9, updatedAt: d9),
                TradeDetail(documentId: "td_hpg_2", rawId: 7, tradeDocumentId: "trd_hpg_closed_sl", price: 27_200, type: .sell, volume: 4_000, signal: .stoploss, date: d1, note: "Cắt lỗ đúng kế hoạch", createdAt: d1, updatedAt: d1)
            ],
            createdAt: d9,
            updatedAt: d1
        )

        // Derivative VN30F1M Trade
        let t5 = Trade(
            documentId: "trd_vn30f_today",
            rawId: 105,
            type: .long,
            tradeStatus: .open,
            note: "Long VN30F1M khi vượt VWAP 1341.0 phiên sáng.",
            date: now,
            accountDocumentId: accDeriv.documentId,
            symbolDocumentId: "sym_vn30f1m",
            symbolName: "VN30F1M",
            strategyDocumentId: stratTrendFollow.documentId,
            strategyName: stratTrendFollow.name,
            scored: 9,
            pnl: nil,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: [
                TradeDetail(documentId: "td_vn30f_1", rawId: 8, tradeDocumentId: "trd_vn30f_today", price: 1_341.0, type: .buy, volume: 5, signal: .entry, date: now, note: "Long 5 HĐ tại 1341.0, SL 1337.5, TP 1352.0", createdAt: now, updatedAt: now)
            ],
            createdAt: now,
            updatedAt: now
        )

        [t1, t2, t3, t4, t5].forEach { db.saveTrade($0) }

        // Sample Daily & Weekly Plans
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let todayStr = df.string(from: now)

        let dailyPlan = TradingPlan(
            documentId: "plan_daily_today",
            rawId: 1,
            accountId: accVN.documentId,
            accountName: accVN.name,
            title: "Kế hoạch giao dịch phiên \(todayStr)",
            scope: .daily,
            planDate: todayStr,
            weekStart: nil,
            weekEnd: nil,
            session: "Cả ngày",
            marketContext: "VNINDEX giữ vững trên MA20 (1,265 điểm), dòng tiền lan tỏa nhóm Công nghệ & Bán lẻ.",
            symbols: "FPT, MWG, SSI",
            entryPlan: "Chỉ giải ngân khi giá vượt nền tích lũy với thanh khoản > 1.5x trung bình 20 phiên. Không mua đuổi khi cổ phiếu đã kéo quá 3% từ nền.",
            riskPlan: "Rủi ro tối đa 1.0% NAV/lệnh (~5 triệu VNĐ). Đặt dừng lỗ ngay dưới đáy cây nến breakout.",
            checklist: "- Kiểm tra xu hướng VNINDEX & nhóm ngành dẫn dắt\n- Xác nhận khối lượng đột biến\n- Tính sẵn khối lượng trong tab Calc Volume trước khi vào lệnh",
            reviewNotes: "Đã giải ngân đúng kế hoạch MWG và nhồi thêm FPT.",
            status: .active,
            maxTrades: 3,
            createdAt: now,
            updatedAt: now
        )
        db.savePlan(dailyPlan)

        // Sample Roadmap
        let roadmap = RoadmapItem(
            documentId: "rm_vn_q4",
            rawId: 1,
            accountDocumentId: accVN.documentId,
            settingDocumentId: setVN.documentId,
            startingBalance: 500_000_000,
            targetGrowthPercent: 25.0,
            plannedTrades: 25,
            riskPercent: 1.0,
            rewardMultiple: 2.2,
            maxDrawDownPercent: 8.0,
            status: .process,
            targetBalance: 625_000_000,
            profitTarget: 125_000_000,
            winRateEstimate: 55.0,
            snapshotJson: nil,
            createdAt: now,
            updatedAt: now
        )
        db.saveRoadmap(roadmap)
        db.markAllSynced()
    }
}

