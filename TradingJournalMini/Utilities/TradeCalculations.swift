import Foundation

// MARK: - Market Classifier & Point Value (mirrors marketClassifier.js)

enum MarketKind: String, Codable {
    case stock
    case crypto
    case derivative
}

struct TradeCostRates: Hashable {
    var kind: MarketKind
    var feeRate: Double         // % of fill value
    var sellTaxRate: Double     // % of sell value
    var feePerContract: Double  // Fixed fee per contract (VN30F1M)
}

enum MarketClassifier {
    static let vnDerivativePointValue: Double = 100_000.0

    static func isVnDerivativeSymbol(_ symbolName: String) -> Bool {
        let sym = symbolName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return sym == "VN30F1M" || sym.hasPrefix("41I")
    }

    static func isCryptoSymbol(_ symbolName: String) -> Bool {
        let sym = symbolName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return sym.contains("USDT") || sym.contains("USDC") || sym.contains("BUSD")
            || sym.hasSuffix(".P") || sym.contains("PERP") || sym.hasPrefix("BINANCE:")
    }

    static func isCryptoAccount(_ account: Account?) -> Bool {
        let market = (account?.marketName ?? "").uppercased()
        let name = (account?.name ?? "").uppercased()
        return market.contains("CRYPTO") || name.contains("BINANCE")
    }

    static func isDerivativeContext(account: Account?, symbolName: String) -> Bool {
        let market = (account?.marketName ?? "").uppercased()
        let name = (account?.name ?? "").uppercased()
        if market.contains("DERIVATIVE") || market.contains("PHÁI SINH") || market.contains("FUTURES_VN")
            || name.contains("DERIVATIVE") || name.contains("PHÁI SINH") {
            return true
        }
        return isVnDerivativeSymbol(symbolName) && !isCryptoAccount(account)
    }

    static func classify(account: Account?, symbolName: String) -> MarketKind {
        if isDerivativeContext(account: account, symbolName: symbolName) {
            return .derivative
        }
        if isCryptoAccount(account) || isCryptoSymbol(symbolName) {
            return .crypto
        }
        return .stock
    }

    static func pointValue(for trade: Trade, account: Account?) -> Double {
        isDerivativeContext(account: account, symbolName: trade.symbolName) ? vnDerivativePointValue : 1.0
    }
}

// MARK: - Trade Lifecycle & PnL Engine (mirrors tradeCalculations.js)

struct TradeLifecycleStep: Identifiable, Hashable {
    var id: String { detail.documentId }
    var detail: TradeDetail
    var action: String          // "open" or "close"
    var isFuture: Bool
    var addType: String?        // "initial", "averageDown", "pyramid"
    var addGapPct: Double?
    var price: Double
    var volume: Double
    var closedVolume: Double
    var position: Double
    var avgCost: Double
    var realized: Double
    var realizedTotal: Double
    var markPnl: Double
    var cost: Double
    var costTotal: Double
    var netMarkPnl: Double
}

struct TradeLifecycleSummary: Hashable {
    var openVolume: Double
    var avgCost: Double
    var entryVolume: Double
    var exitVolume: Double
    var realized: Double
    var unrealized: Double?
    var total: Double?
    var costs: Double
    var netRealized: Double
    var netTotal: Double?
    var isFlat: Bool
    var overClosedVolume: Double
    var averageDownCount: Int
    var pyramidCount: Int
    var costRates: TradeCostRates
}

struct TradeLifecycleResult: Hashable {
    var steps: [TradeLifecycleStep]
    var summary: TradeLifecycleSummary
}

enum TradeCalculator {
    static func isFutureDetail(_ detail: TradeDetail, trade: Trade, now: Date = Date()) -> Bool {
        if trade.tradeStatus == .closed { return false }
        return detail.date > now
    }

    static func getFirstEntryDetail(_ trade: Trade) -> TradeDetail? {
        let sorted = trade.tradeDetails
            .filter { !$0.isDeleted }
            .sorted { $0.date < $1.date }
        return sorted.first(where: { $0.signal == .entry }) ?? sorted.first
    }

    static func getTradeEntryDate(_ trade: Trade) -> Date {
        getFirstEntryDetail(trade)?.date ?? trade.date
    }

    static func getTradeCostRates(trade: Trade, account: Account?) -> TradeCostRates {
        let kind = MarketClassifier.classify(account: account, symbolName: trade.symbolName)
        switch kind {
        case .derivative:
            return TradeCostRates(
                kind: .derivative,
                feeRate: 0,
                sellTaxRate: 0,
                feePerContract: account?.feePerContract ?? 20_000
            )
        case .crypto:
            return TradeCostRates(
                kind: .crypto,
                feeRate: account?.feeRate ?? 0.1,
                sellTaxRate: 0,
                feePerContract: 0
            )
        case .stock:
            return TradeCostRates(
                kind: .stock,
                feeRate: account?.feeRate ?? 0.15,
                sellTaxRate: account?.sellTaxRate ?? 0.1,
                feePerContract: 0
            )
        }
    }

    static func getDetailCost(detail: TradeDetail, rates: TradeCostRates, pointValue: Double = 1.0) -> Double {
        let volume = abs(detail.volume)
        if rates.kind == .derivative {
            return volume * rates.feePerContract
        }
        let value = abs(detail.price * volume * pointValue)
        let buySellFee = value * (rates.feeRate / 100.0)
        let sellTax = detail.type == .sell ? value * (rates.sellTaxRate / 100.0) : 0.0
        return buySellFee + sellTax
    }

    static func getInterpolatedTradePrice(trade: Trade, currentPrice: Double? = nil, now: Date = Date()) -> Double? {
        if let explicit = currentPrice, explicit > 0 { return explicit }
        if trade.tradeStatus == .closed { return nil }

        let isLong = trade.type != .short
        let entrySide: OrderSide = isLong ? .buy : .sell
        let sorted = trade.tradeDetails.filter { !$0.isDeleted }.sorted { $0.date < $1.date }

        let executedEntries = sorted.filter {
            $0.type == entrySide && !isFutureDetail($0, trade: trade, now: now) && $0.price > 0
        }
        let futureExits = sorted.filter {
            $0.type != entrySide && isFutureDetail($0, trade: trade, now: now) && $0.price > 0
        }
        guard !executedEntries.isEmpty, !futureExits.isEmpty else { return nil }

        func weightedAvg(_ list: [TradeDetail]) -> Double {
            let totalVol = list.reduce(0.0) { $0 + $1.volume }
            guard totalVol > 0 else { return list.first?.price ?? 0 }
            let totalVal = list.reduce(0.0) { $0 + ($1.price * $1.volume) }
            return totalVal / totalVol
        }

        let entryPrice = weightedAvg(executedEntries)
        let targetPrice = weightedAvg(futureExits)
        let entryTime = (executedEntries.first?.date ?? trade.date).timeIntervalSince1970
        let targetTime = (futureExits.last?.date ?? now).timeIntervalSince1970
        if targetTime <= entryTime { return targetPrice }

        let ratio = min(1.0, max(0.0, (now.timeIntervalSince1970 - entryTime) / (targetTime - entryTime)))
        return entryPrice + (targetPrice - entryPrice) * ratio
    }

    /// Raw PnL in price units (Cashflow + Remaining Inventory * Effective Price)
    static func calculateTradePnL(_ trade: Trade, currentPrice: Double? = nil, now: Date = Date()) -> Double {
        let executed = trade.tradeDetails
            .filter { !$0.isDeleted && !isFutureDetail($0, trade: trade, now: now) }

        var cashflow = 0.0
        var netVolume = 0.0
        for d in executed {
            let val = d.price * d.volume
            if d.type == .sell {
                cashflow += val
                netVolume -= d.volume
            } else {
                cashflow -= val
                netVolume += d.volume
            }
        }

        if let effectivePrice = getInterpolatedTradePrice(trade: trade, currentPrice: currentPrice, now: now) {
            return cashflow + (netVolume * effectivePrice)
        }
        return cashflow
    }

    /// PnL in Account currency (applies 100,000 VND/point multiplier for VN30F1M / Derivative accounts)
    static func calculateDerivativeTradePnL(_ trade: Trade, currentPrice: Double? = nil, account: Account? = nil) -> Double {
        calculateTradePnL(trade, currentPrice: currentPrice) * MarketClassifier.pointValue(for: trade, account: account)
    }

    /// Step-by-step lifecycle matching buildTradeLifecycle in tradeCalculations.js
    static func buildTradeLifecycle(_ trade: Trade, currentPrice: Double? = nil, account: Account? = nil, now: Date = Date()) -> TradeLifecycleResult {
        let isLong = trade.type != .short
        let direction: Double = isLong ? 1.0 : -1.0
        let entrySide: OrderSide = isLong ? .buy : .sell
        let pointValue = MarketClassifier.pointValue(for: trade, account: account)
        let costRates = getTradeCostRates(trade: trade, account: account)
        let sortedDetails = trade.tradeDetails.filter { !$0.isDeleted }.sorted { $0.date < $1.date }

        var position = 0.0
        var avgCost = 0.0
        var realizedTotal = 0.0
        var costTotal = 0.0
        var entryVolume = 0.0
        var exitVolume = 0.0
        var overClosedVolume = 0.0
        var averageDownCount = 0
        var pyramidCount = 0
        var executedStepCount = 0

        var steps: [TradeLifecycleStep] = []

        for detail in sortedDetails {
            let price = detail.price
            let volume = detail.volume
            let action = detail.type == entrySide ? "open" : "close"
            let isFuture = isFutureDetail(detail, trade: trade, now: now)

            if isFuture {
                let projectedClosedVolume = action == "close" ? min(volume, position) : 0
                let projectedRealized = action == "close"
                    ? (price - avgCost) * projectedClosedVolume * direction * pointValue
                    : 0
                let markPnl = realizedTotal + (price - avgCost) * position * direction * pointValue
                steps.append(TradeLifecycleStep(
                    detail: detail,
                    action: action,
                    isFuture: true,
                    addType: action == "open" ? "initial" : nil,
                    addGapPct: nil,
                    price: price,
                    volume: volume,
                    closedVolume: projectedClosedVolume,
                    position: position,
                    avgCost: avgCost,
                    realized: projectedRealized,
                    realizedTotal: realizedTotal,
                    markPnl: markPnl,
                    cost: 0,
                    costTotal: costTotal,
                    netMarkPnl: markPnl - costTotal
                ))
                continue
            }

            executedStepCount += 1
            let cost = getDetailCost(detail: detail, rates: costRates, pointValue: pointValue)
            var realized = 0.0
            var closedVolume = 0.0
            var addType: String? = nil
            var addGapPct: Double? = nil

            if action == "open" {
                if position > 0 && avgCost > 0 {
                    let gap = ((price - avgCost) / avgCost) * 100.0 * direction
                    addGapPct = gap
                    addType = gap < 0 ? "averageDown" : "pyramid"
                    if addType == "averageDown" { averageDownCount += 1 } else { pyramidCount += 1 }
                } else {
                    addType = "initial"
                }
                avgCost = (position + volume) > 0 ? ((avgCost * position + price * volume) / (position + volume)) : 0
                position += volume
                entryVolume += volume
            } else {
                closedVolume = min(volume, position)
                overClosedVolume += (volume - closedVolume)
                realized = (price - avgCost) * closedVolume * direction * pointValue
                realizedTotal += realized
                position -= closedVolume
                exitVolume += volume
                if position <= 0 {
                    position = 0
                    avgCost = 0
                }
            }
            costTotal += cost
            let markPnl = realizedTotal + (price - avgCost) * position * direction * pointValue

            steps.append(TradeLifecycleStep(
                detail: detail,
                action: action,
                isFuture: false,
                addType: addType,
                addGapPct: addGapPct,
                price: price,
                volume: volume,
                closedVolume: closedVolume,
                position: position,
                avgCost: avgCost,
                realized: realized,
                realizedTotal: realizedTotal,
                markPnl: markPnl,
                cost: cost,
                costTotal: costTotal,
                netMarkPnl: markPnl - costTotal
            ))
        }

        let markPrice = getInterpolatedTradePrice(trade: trade, currentPrice: currentPrice, now: now)
        let unrealized: Double? = position > 0
            ? (markPrice != nil ? (markPrice! - avgCost) * position * direction * pointValue : nil)
            : 0.0
        let total: Double? = unrealized == nil ? realizedTotal : (realizedTotal + (unrealized ?? 0))

        let summary = TradeLifecycleSummary(
            openVolume: position,
            avgCost: avgCost,
            entryVolume: entryVolume,
            exitVolume: exitVolume,
            realized: realizedTotal,
            unrealized: unrealized,
            total: total,
            costs: costTotal,
            netRealized: realizedTotal - costTotal,
            netTotal: total.map { $0 - costTotal },
            isFlat: executedStepCount > 0 && position == 0,
            overClosedVolume: overClosedVolume,
            averageDownCount: averageDownCount,
            pyramidCount: pyramidCount,
            costRates: costRates
        )

        return TradeLifecycleResult(steps: steps, summary: summary)
    }
}

// MARK: - Roadmap & Compounding Engine (mirrors roadmapCalculations.js)

struct RoadmapStepRow: Identifiable, Hashable {
    var id: Int { tradeNumber }
    var tradeNumber: Int
    var startEquity: Double
    var winEquity: Double
    var lossEquity: Double
    var winProfit: Double
    var lossAmount: Double
    var progress: Double
}

struct RoadmapProjection: Hashable {
    var baseBalance: Double
    var targetBalance: Double
    var profitTarget: Double
    var riskPct: Double
    var rewardPct: Double
    var rewardMultiple: Double
    var winFactor: Double
    var lossFactor: Double
    var winsOnlyNeeded: Int?
    var winsNeededInPlannedTrades: Int?
    var expectedWinsInPlannedTrades: Int
    var estimatedTradesToGoal: Int?
    var equityAfterPlannedTradesIfAllWins: Double
    var winRateEstimate: Double
    var lossBudget: Double
    var maxDrawDownLossBudget: Double
    var rows: [RoadmapStepRow]
}

enum RoadmapCalculator {
    static func buildProjection(
        startBalance: Double,
        riskPercent: Double,
        targetGrowthPercent: Double,
        rewardMultiple: Double,
        plannedTrades: Int,
        winRateEstimate: Double,
        maxDrawDownPercent: Double = 10.0
    ) -> RoadmapProjection {
        let base = max(startBalance, 0)
        let riskPct = max(riskPercent, 0)
        let growthPct = max(targetGrowthPercent, 0)
        let rr = max(rewardMultiple, 0)
        let tradesCount = max(plannedTrades, 0)
        let winRate = min(max(winRateEstimate / 100.0, 0), 1.0)

        let targetBalance = base * (1.0 + growthPct / 100.0)
        let profitTarget = targetBalance - base
        let riskFactor = riskPct / 100.0
        let winFactor = 1.0 + (riskFactor * rr)
        let lossFactor = 1.0 - riskFactor
        let rewardPct = riskPct * rr

        let winOnlyLog = winFactor > 1.0 ? log(winFactor) : 0.0
        let goalLog = (base > 0 && targetBalance > 0) ? log(targetBalance / base) : 0.0
        let lossesLog = lossFactor > 0 ? log(lossFactor) : -.infinity

        let winsOnlyNeeded: Int? = winOnlyLog > 0 ? Int(ceil(goalLog / winOnlyLog)) : nil

        var winsNeededInPlannedTrades: Int? = nil
        if tradesCount > 0 && winFactor > 0 && lossFactor > 0 {
            let numerator = goalLog - (Double(tradesCount) * lossesLog)
            let denominator = log(winFactor) - lossesLog
            if denominator > 0 {
                let raw = Int(ceil(numerator / denominator))
                winsNeededInPlannedTrades = max(0, min(tradesCount, raw))
            }
        }

        let expectedLogGrowth: Double = (winRate > 0 && winRate < 1 && winFactor > 0 && lossFactor > 0)
            ? (winRate * log(winFactor)) + ((1.0 - winRate) * log(lossFactor))
            : 0.0

        let estimatedTradesToGoal: Int? = winRate == 1.0
            ? winsOnlyNeeded
            : (expectedLogGrowth > 0 ? Int(ceil(goalLog / expectedLogGrowth)) : nil)

        let expectedWins = tradesCount > 0 ? Int((Double(tradesCount) * winRate).rounded()) : 0
        let equityIfAllWins = tradesCount > 0 ? base * pow(winFactor, Double(tradesCount)) : base
        let lossBudget = base * riskFactor
        let maxDDLossBudget = base * (max(maxDrawDownPercent, 0) / 100.0)

        let rows: [RoadmapStepRow] = (0..<tradesCount).map { idx in
            let tradeNum = idx + 1
            let startEq = base * pow(winFactor, Double(idx))
            let winEq = startEq * winFactor
            let lossEq = startEq * lossFactor
            let winProf = winEq - startEq
            let lossAmt = startEq - lossEq
            let prog = profitTarget > 0 ? min(100.0, ((winEq - base) / profitTarget) * 100.0) : 0.0
            return RoadmapStepRow(
                tradeNumber: tradeNum,
                startEquity: startEq,
                winEquity: winEq,
                lossEquity: lossEq,
                winProfit: winProf,
                lossAmount: lossAmt,
                progress: prog
            )
        }

        return RoadmapProjection(
            baseBalance: base,
            targetBalance: targetBalance,
            profitTarget: profitTarget,
            riskPct: riskPct,
            rewardPct: rewardPct,
            rewardMultiple: rr,
            winFactor: winFactor,
            lossFactor: lossFactor,
            winsOnlyNeeded: winsOnlyNeeded,
            winsNeededInPlannedTrades: winsNeededInPlannedTrades,
            expectedWinsInPlannedTrades: expectedWins,
            estimatedTradesToGoal: estimatedTradesToGoal,
            equityAfterPlannedTradesIfAllWins: equityIfAllWins,
            winRateEstimate: winRate * 100.0,
            lossBudget: lossBudget,
            maxDrawDownLossBudget: maxDDLossBudget,
            rows: rows
        )
    }
}

// MARK: - Risk & Monitor Analytics (mirrors riskManagement.js)

struct EquityCurvePoint: Identifiable, Hashable {
    var id: String { day }
    var day: String
    var date: Date
    var equity: Double
    var dailyPnl: Double
    var drawdownPct: Double
}

struct AccountPerformanceMetrics: Hashable {
    var initialBalance: Double
    var currentEquity: Double
    var realizedPnl: Double
    var unrealizedPnl: Double
    var totalPnl: Double
    var returnPct: Double
    var closedTradeCount: Int
    var openTradeCount: Int
    var winCount: Int
    var lossCount: Int
    var winRate: Double
    var profitFactor: Double?
    var expectancy: Double
    var avgWin: Double
    var avgLoss: Double
    var maxLosingStreak: Int
    var maxDrawdownPct: Double
    var currentDrawdownPct: Double
    var openExposureValue: Double
    var openExposurePct: Double
    var verdictLevel: String        // "ok", "watch", "action", "nodata"
    var verdictReasons: [String]
    var equityCurve: [EquityCurvePoint]
}

enum RiskAnalyticsEngine {
    static func analyzeAccount(account: Account, trades: [Trade], symbolPrices: [String: Double]) -> AccountPerformanceMetrics {
        let activeTrades = trades.filter { !$0.isDeleted && !$0.backtest }
        let closedTrades = activeTrades
            .filter { $0.tradeStatus == .closed }
            .sorted { $0.date < $1.date }
        let openTrades = activeTrades.filter { $0.tradeStatus != .closed }

        var realizedPnl = 0.0
        var wins = 0
        var losses = 0
        var grossWin = 0.0
        var grossLoss = 0.0
        var streak = 0
        var maxLosingStreak = 0

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        var pnlByDay: [String: (date: Date, pnl: Double)] = [:]

        for trade in closedTrades {
            let pnl = TradeCalculator.calculateDerivativeTradePnL(trade, currentPrice: nil, account: account)
            realizedPnl += pnl
            if pnl > 0 {
                wins += 1
                grossWin += pnl
                streak = 0
            } else if pnl < 0 {
                losses += 1
                grossLoss += abs(pnl)
                streak += 1
                maxLosingStreak = max(maxLosingStreak, streak)
            }
            let dayStr = dayFormatter.string(from: trade.date)
            let prev = pnlByDay[dayStr]?.pnl ?? 0.0
            pnlByDay[dayStr] = (trade.date, prev + pnl)
        }

        var unrealizedPnl = 0.0
        var openExposureValue = 0.0
        for trade in openTrades {
            let markPrice = symbolPrices[trade.symbolName.uppercased()]
            let lifecycle = TradeCalculator.buildTradeLifecycle(trade, currentPrice: markPrice, account: account)
            unrealizedPnl += lifecycle.summary.unrealized ?? lifecycle.summary.realized
            let ptVal = MarketClassifier.pointValue(for: trade, account: account)
            openExposureValue += lifecycle.summary.openVolume * (markPrice ?? lifecycle.summary.avgCost) * ptVal
        }

        let totalPnl = realizedPnl + unrealizedPnl
        let currentEquity = account.initialBalance + totalPnl
        let returnPct = account.initialBalance > 0 ? (totalPnl / account.initialBalance) * 100.0 : 0.0
        let closedCount = closedTrades.count
        let winRate = closedCount > 0 ? (Double(wins) / Double(closedCount)) * 100.0 : 0.0
        let profitFactor: Double? = grossLoss > 0 ? (grossWin / grossLoss) : (grossWin > 0 ? 99.9 : nil)
        let expectancy = closedCount > 0 ? ((grossWin - grossLoss) / Double(closedCount)) : 0.0
        let avgWin = wins > 0 ? (grossWin / Double(wins)) : 0.0
        let avgLoss = losses > 0 ? (grossLoss / Double(losses)) : 0.0

        // Build Equity Curve
        var runningEquity = account.initialBalance
        var peakEquity = runningEquity
        var maxDDPct = 0.0
        var curve: [EquityCurvePoint] = []

        let sortedDays = pnlByDay.keys.sorted()
        if let firstDay = sortedDays.first, let firstDate = pnlByDay[firstDay]?.date {
            let startDate = Calendar.current.date(byAdding: .day, value: -1, to: firstDate) ?? firstDate
            curve.append(EquityCurvePoint(
                day: "Start",
                date: startDate,
                equity: account.initialBalance,
                dailyPnl: 0,
                drawdownPct: 0
            ))
        }

        for day in sortedDays {
            guard let entry = pnlByDay[day] else { continue }
            runningEquity += entry.pnl
            peakEquity = max(peakEquity, runningEquity)
            let ddPct = peakEquity > 0 ? max(0.0, ((peakEquity - runningEquity) / peakEquity) * 100.0) : 0.0
            maxDDPct = max(maxDDPct, ddPct)
            curve.append(EquityCurvePoint(
                day: day,
                date: entry.date,
                equity: runningEquity,
                dailyPnl: entry.pnl,
                drawdownPct: ddPct
            ))
        }

        if unrealizedPnl != 0 {
            let liveEq = runningEquity + unrealizedPnl
            peakEquity = max(peakEquity, liveEq)
            let ddPct = peakEquity > 0 ? max(0.0, ((peakEquity - liveEq) / peakEquity) * 100.0) : 0.0
            maxDDPct = max(maxDDPct, ddPct)
            curve.append(EquityCurvePoint(
                day: "Hiện tại",
                date: Date(),
                equity: liveEq,
                dailyPnl: unrealizedPnl,
                drawdownPct: ddPct
            ))
        }

        let currentDDPct = curve.last?.drawdownPct ?? 0.0
        let openExposurePct = currentEquity > 0 ? (openExposureValue / currentEquity) * 100.0 : 0.0
        let ddLimitPct = account.setting?.maxDrawDown

        // Assess account verdict (mirrors assessAccount in riskManagement.js)
        var reasons: [String] = []
        var level = "ok"
        let rank: [String: Int] = ["ok": 0, "nodata": 1, "watch": 2, "action": 3]
        func flag(_ nextLevel: String, _ text: String) {
            reasons.append(text)
            if (rank[nextLevel] ?? 0) > (rank[level] ?? 0) {
                level = nextLevel
            }
        }

        if (account.timeframe ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            flag("watch", "Chưa đặt timeframe cho tài khoản")
        }
        if closedCount < 10 {
            flag("nodata", "Mới có \(closedCount) lệnh đóng, cần tối thiểu 10 lệnh để đánh giá hệ thống")
        } else {
            if let pf = profitFactor, pf < 1.0 {
                flag("action", String(format: "Profit Factor %.2f < 1.0: Hệ thống đang âm kỳ vọng, cần rà soát lại", pf))
            }
            if maxLosingStreak >= 5 {
                flag("watch", "Chuỗi thua liên tiếp dài nhất: \(maxLosingStreak) lệnh")
            }
        }

        if let limit = ddLimitPct, limit > 0 {
            if currentDDPct >= limit {
                flag("action", String(format: "Vượt ngưỡng Max DD: %.1f%% ≥ %.1f%% — tạm dừng mở lệnh mới!", currentDDPct, limit))
            } else if currentDDPct >= limit * 0.8 {
                flag("watch", String(format: "Drawdown hiện tại %.1f%% đã chạm %.0f%% hạn mức Max DD (%.1f%%)", currentDDPct, (currentDDPct / limit) * 100, limit))
            }
        } else if currentDDPct > 10.0 {
            flag("watch", String(format: "Tài khoản đang sụt giảm %.1f%% từ đỉnh", currentDDPct))
        }

        if openExposurePct > 100.0 {
            flag("watch", String(format: "Tỷ trọng vị thế mở %.0f%% NAV (đang sử dụng Margin/Đòn bẩy)", openExposurePct))
        }

        if level == "ok" && reasons.isEmpty {
            reasons.append("Hệ thống ổn định: Kỷ luật và hiệu suất nằm trong vùng an toàn.")
        }

        return AccountPerformanceMetrics(
            initialBalance: account.initialBalance,
            currentEquity: currentEquity,
            realizedPnl: realizedPnl,
            unrealizedPnl: unrealizedPnl,
            totalPnl: totalPnl,
            returnPct: returnPct,
            closedTradeCount: closedCount,
            openTradeCount: openTrades.count,
            winCount: wins,
            lossCount: losses,
            winRate: winRate,
            profitFactor: profitFactor,
            expectancy: expectancy,
            avgWin: avgWin,
            avgLoss: avgLoss,
            maxLosingStreak: maxLosingStreak,
            maxDrawdownPct: maxDDPct,
            currentDrawdownPct: currentDDPct,
            openExposureValue: openExposureValue,
            openExposurePct: openExposurePct,
            verdictLevel: level,
            verdictReasons: reasons,
            equityCurve: curve
        )
    }
}

// MARK: - Money & Number Formatting (mirrors formatMoney.js & formatNumber.js)

enum MoneyFormatter {
    static func format(_ amount: Double, currency: String = "VND", compact: Bool = false) -> String {
        let sign = amount < 0 ? "-" : ""
        let absVal = abs(amount)
        let isVND = currency.uppercased() == "VND"

        if compact {
            if isVND {
                if absVal >= 1_000_000_000 {
                    return String(format: "%@%.2f tỷ", sign, absVal / 1_000_000_000)
                } else if absVal >= 1_000_000 {
                    return String(format: "%@%.1f tr", sign, absVal / 1_000_000)
                } else if absVal >= 1_000 {
                    return String(format: "%@%.0fK", sign, absVal / 1_000)
                }
            } else {
                if absVal >= 1_000_000 {
                    return String(format: "%@$%.2fM", sign, absVal / 1_000_000)
                } else if absVal >= 1_000 {
                    return String(format: "%@$%.1fK", sign, absVal / 1_000)
                }
            }
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = isVND ? 0 : 2
        formatter.minimumFractionDigits = isVND ? 0 : 2

        let formatted = formatter.string(from: NSNumber(value: absVal)) ?? "\(absVal)"
        return isVND ? "\(sign)\(formatted) ₫" : "\(sign)$\(formatted)"
    }

    static func formatSigned(_ amount: Double, currency: String = "VND", compact: Bool = false) -> String {
        let prefix = amount > 0 ? "+" : ""
        return prefix + format(amount, currency: currency, compact: compact)
    }

    static func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 1000 ? 1 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatVolume(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

