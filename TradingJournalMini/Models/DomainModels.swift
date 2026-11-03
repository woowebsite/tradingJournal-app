import Foundation

// MARK: - Strapi Blocks <-> Plain Text Helper

/// Converts between Strapi v5 Rich Text `blocks` array and plain String for seamless Desktop <-> iOS sync.
enum StrapiBlocksConverter {
    static func blocksToPlainText(_ anyValue: Any?) -> String {
        if let str = anyValue as? String {
            return str
        }
        guard let blocks = anyValue as? [[String: Any]] else {
            return ""
        }
        var lines: [String] = []
        for block in blocks {
            if let children = block["children"] as? [[String: Any]] {
                let text = children.compactMap { $0["text"] as? String }.joined()
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func plainTextToBlocks(_ text: String) -> [[String: Any]] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: "\n").map { line in
            [
                "type": "paragraph",
                "children": [
                    [
                        "type": "text",
                        "text": line
                    ]
                ]
            ]
        }
    }
}

// MARK: - Enums

enum TradeDirection: String, Codable, CaseIterable, Identifiable {
    case long = "Long"
    case short = "Short"
    var id: String { rawValue }
}

enum TradeStatus: String, Codable, CaseIterable, Identifiable {
    case open = "Open"
    case closed = "Closed"
    case scaleIn = "ScaleIn"
    case scaleOut = "ScaleOut"
    var id: String { rawValue }

    var labelVN: String {
        switch self {
        case .open: return "Đang mở"
        case .closed: return "Đã đóng"
        case .scaleIn: return "Scale In"
        case .scaleOut: return "Scale Out"
        }
    }
}

enum OrderSide: String, Codable, CaseIterable, Identifiable {
    case buy = "Buy"
    case sell = "Sell"
    var id: String { rawValue }
}

enum TradeSignalType: String, Codable, CaseIterable, Identifiable {
    case entry = "Entry"
    case takeProfit = "TakeProfit"
    case stoploss = "Stoploss"
    case exit = "Exit"
    var id: String { rawValue }
}

enum PlanScope: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    var id: String { rawValue }
}

enum PlanStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Draft"
    case active = "Active"
    case done = "Done"
    case skipped = "Skipped"
    var id: String { rawValue }
}

enum RoadmapStatus: String, Codable, CaseIterable, Identifiable {
    case unprocess = "unprocess"
    case process = "process"
    case completed = "completed"
    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .unprocess: return "Chưa thực hiện"
        case .process: return "Đang chạy"
        case .completed: return "Hoàn thành"
        }
    }
}

// MARK: - Core Entities

struct MarketItem: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var name: String
    var description: String?
    var updatedAt: Date
    var isDirty: Bool = false

    var id: String { documentId }
}

struct RiskSetting: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var name: String
    var riskPerTrade: Double     // % per trade, e.g. 1.0
    var maxDrawDown: Double      // % max drawdown limit, e.g. 10.0
    var capitalRisk: Double      // % max open capital risk, e.g. 15.0
    var accountDocumentId: String?
    var updatedAt: Date
    var isDirty: Bool = false

    var id: String { documentId }
}

struct StrategyItem: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var name: String
    var description: String?
    var type: String             // "Rules", "Webhook", "Python"
    var strategyFile: String?
    var template: String?
    var updatedAt: Date
    var isDirty: Bool = false

    var id: String { documentId }
}

struct AccountAllocationRule: Codable, Hashable {
    var targetPercent: Double?
    var role: String?
    var note: String?
}

struct Account: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var name: String
    var description: String?
    var initialBalance: Double
    var cash: Double?
    var margin: Double?
    var currency: String         // "VND" or "USD"
    var marketDocumentId: String?
    var marketName: String?
    var settingDocumentId: String?
    var setting: RiskSetting?
    var strategyDocumentId: String?
    var strategyName: String?
    var volumeFormat: String?
    var moneyFormat: String?
    var feeRate: Double?
    var sellTaxRate: Double?
    var feePerContract: Double?
    var maxPositionPct: Double?
    var maxAverageDown: Int?
    var timeframe: String?
    var allocationJson: String?
    var updatedAt: Date
    var isDirty: Bool = false

    var id: String { documentId }
}

struct SymbolItem: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var name: String             // e.g. "FPT", "VN30F1M", "BTCUSDT"
    var description: String?
    var exchange: String?
    var shortName: String?
    var industry: String?
    var sector: String?
    var marketDocumentId: String?
    var lastClose: Double?
    var prevClose: Double?
    var lastVolume: Double?
    var avgVolume20d: Double?
    var ma20: Double?
    var lastPriceDate: String?
    var updatedAt: Date
    var isDirty: Bool = false

    var id: String { documentId }

    var changePct: Double? {
        guard let last = lastClose, let prev = prevClose, prev > 0 else { return nil }
        return ((last - prev) / prev) * 100.0
    }

    var volumeRatio: Double? {
        guard let vol = lastVolume, let avg = avgVolume20d, avg > 0 else { return nil }
        return vol / avg
    }
}

struct TradeDetail: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var tradeDocumentId: String
    var price: Double
    var type: OrderSide
    var volume: Double
    var signal: TradeSignalType
    var date: Date
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool = false
    var isDeleted: Bool = false

    var id: String { documentId }
}

struct Trade: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var type: TradeDirection
    var tradeStatus: TradeStatus
    var note: String
    var date: Date
    var accountDocumentId: String
    var symbolDocumentId: String?
    var symbolName: String
    var strategyDocumentId: String?
    var strategyName: String?
    var scored: Int
    var pnl: Double?
    var forwardTest: Bool
    var backtest: Bool
    var marketSnapshotJson: String?
    var tradeDetails: [TradeDetail]
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool = false
    var isDeleted: Bool = false

    var id: String { documentId }
}

struct TradingPlan: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var accountId: String
    var accountName: String
    var title: String
    var scope: PlanScope
    var planDate: String?        // YYYY-MM-DD
    var weekStart: String?       // YYYY-MM-DD
    var weekEnd: String?         // YYYY-MM-DD
    var session: String?
    var marketContext: String
    var symbols: String
    var entryPlan: String
    var riskPlan: String
    var checklist: String
    var reviewNotes: String
    var status: PlanStatus
    var maxTrades: Int
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool = false
    var isDeleted: Bool = false

    var id: String { documentId }
}

struct RoadmapItem: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var accountDocumentId: String
    var settingDocumentId: String?
    var startingBalance: Double
    var targetGrowthPercent: Double
    var plannedTrades: Int
    var riskPercent: Double
    var rewardMultiple: Double
    var maxDrawDownPercent: Double
    var status: RoadmapStatus
    var targetBalance: Double
    var profitTarget: Double
    var winRateEstimate: Double
    var snapshotJson: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool = false
    var isDeleted: Bool = false

    var id: String { documentId }
}

struct AllocationSnapshot: Identifiable, Codable, Hashable {
    var documentId: String
    var rawId: Int?
    var name: String
    var fromDate: String?
    var toDate: String?
    var accountsJson: String?
    var settingsJson: String?
    var updatedAt: Date
    var isDirty: Bool = false

    var id: String { documentId }
}

// MARK: - Canonical Sync Snapshot Payload (Desktop <-> iOS)

/// Portable JSON Snapshot format designed to sync seamlessly between Desktop Strapi v5 (PostgreSQL) and iPhone SQLite.
struct TradingJournalSyncSnapshot: Codable {
    var schemaVersion: Int = 1
    var exportedAt: Date
    var sourceDevice: String      // "Desktop-Strapi-v5" or "iOS-TradingJournalMini"
    var accounts: [Account]
    var settings: [RiskSetting]
    var markets: [MarketItem]
    var strategies: [StrategyItem]
    var symbols: [SymbolItem]
    var trades: [Trade]
    var plans: [TradingPlan]
    var roadmaps: [RoadmapItem]
    var allocationSnapshots: [AllocationSnapshot]
    var deletedTradeDocumentIds: [String]?
    var deletedTradeDetailDocumentIds: [String]?
    var deletedPlanDocumentIds: [String]?
    var deletedRoadmapDocumentIds: [String]?
}

