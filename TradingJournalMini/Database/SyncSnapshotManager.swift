import Foundation
import UniformTypeIdentifiers
import SwiftUI

enum SyncImportMode: String, CaseIterable, Identifiable {
    case merge = "Gộp thông minh (2 chiều - Ưu tiên bản mới nhất)"
    case replace = "Ghi đè toàn bộ (Lấy theo file Snapshot)"
    var id: String { rawValue }
}

struct SyncImportSummary {
    var accountsCount: Int
    var symbolsCount: Int
    var strategiesCount: Int
    var tradesCount: Int
    var tradeDetailsCount: Int
    var plansCount: Int
    var roadmapsCount: Int
    var sourceDevice: String
    var exportedAt: Date
}

/// FileDocument wrapper for SwiftUI `.fileExporter`
struct SnapshotJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

final class SyncSnapshotManager {
    static let shared = SyncSnapshotManager()
    private let db = SQLiteDatabase.shared

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let isoWithFrac = ISO8601DateFormatter()
        isoWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = isoWithFrac.date(from: str) { return date }
            if let date = isoPlain.date(from: str) { return date }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let date = df.date(from: String(str.prefix(10))) { return date }
            return Date()
        }
        return d
    }()

    // MARK: - Export JSON Snapshot

    func buildSnapshot() -> TradingJournalSyncSnapshot {
        let allTrades = db.fetchTrades(includeDeleted: true)
        let activeTrades = allTrades.filter { !$0.isDeleted }
        let deletedTradeIds = allTrades.filter { $0.isDeleted }.map(\.documentId)
        let deletedDetailIds = allTrades.flatMap(\.tradeDetails).filter { $0.isDeleted }.map(\.documentId)

        let allPlans = db.fetchPlans(includeDeleted: true)
        let activePlans = allPlans.filter { !$0.isDeleted }
        let deletedPlanIds = allPlans.filter { $0.isDeleted }.map(\.documentId)

        let allRoadmaps = db.fetchRoadmaps(includeDeleted: true)
        let activeRoadmaps = allRoadmaps.filter { !$0.isDeleted }
        let deletedRoadmapIds = allRoadmaps.filter { $0.isDeleted }.map(\.documentId)

        return TradingJournalSyncSnapshot(
            schemaVersion: 1,
            exportedAt: Date(),
            sourceDevice: "iOS-TradingJournalMini",
            accounts: db.fetchAccounts(),
            settings: db.fetchSettings(),
            markets: [],
            strategies: db.fetchStrategies(),
            symbols: db.fetchSymbols(),
            trades: activeTrades,
            plans: activePlans,
            roadmaps: activeRoadmaps,
            allocationSnapshots: [],
            deletedTradeDocumentIds: deletedTradeIds,
            deletedTradeDetailDocumentIds: deletedDetailIds,
            deletedPlanDocumentIds: deletedPlanIds,
            deletedRoadmapDocumentIds: deletedRoadmapIds
        )
    }

    func exportSnapshotData() throws -> Data {
        let snapshot = buildSnapshot()
        return try encoder.encode(snapshot)
    }

    func defaultExportFilename() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        return "tradingjournal_sync_\(df.string(from: Date())).json"
    }

    // MARK: - Import JSON Snapshot

    func importSnapshotData(_ data: Data, mode: SyncImportMode) throws -> SyncImportSummary {
        let snapshot = try decoder.decode(TradingJournalSyncSnapshot.self, from: data)

        if mode == .replace {
            db.clearAllData()
        }

        let existingAccounts = Dictionary(uniqueKeysWithValues: db.fetchAccounts().map { ($0.documentId, $0) })
        let existingSettings = Dictionary(uniqueKeysWithValues: db.fetchSettings().map { ($0.documentId, $0) })
        let existingSymbols = Dictionary(uniqueKeysWithValues: db.fetchSymbols().map { ($0.documentId, $0) })
        let existingStrategies = Dictionary(uniqueKeysWithValues: db.fetchStrategies().map { ($0.documentId, $0) })
        let existingTrades = Dictionary(uniqueKeysWithValues: db.fetchTrades(includeDeleted: true).map { ($0.documentId, $0) })
        let existingPlans = Dictionary(uniqueKeysWithValues: db.fetchPlans(includeDeleted: true).map { ($0.documentId, $0) })
        let existingRoadmaps = Dictionary(uniqueKeysWithValues: db.fetchRoadmaps(includeDeleted: true).map { ($0.documentId, $0) })

        for var setting in snapshot.settings {
            if mode == .merge, let local = existingSettings[setting.documentId], local.isDirty && local.updatedAt > setting.updatedAt {
                continue
            }
            setting.isDirty = false
            db.saveSetting(setting)
        }

        for var strategy in snapshot.strategies {
            if mode == .merge, let local = existingStrategies[strategy.documentId], local.isDirty && local.updatedAt > strategy.updatedAt {
                continue
            }
            strategy.isDirty = false
            db.saveStrategy(strategy)
        }

        for var symbol in snapshot.symbols {
            if mode == .merge, let local = existingSymbols[symbol.documentId], local.isDirty && local.updatedAt > symbol.updatedAt {
                continue
            }
            symbol.isDirty = false
            db.saveSymbol(symbol)
        }

        for var account in snapshot.accounts {
            if mode == .merge, let local = existingAccounts[account.documentId], local.isDirty && local.updatedAt > account.updatedAt {
                continue
            }
            account.isDirty = false
            if var s = account.setting {
                s.isDirty = false
                account.setting = s
            }
            db.saveAccount(account)
        }

        var detailCount = 0
        for var trade in snapshot.trades {
            if mode == .merge, let local = existingTrades[trade.documentId], local.isDirty && local.updatedAt > trade.updatedAt {
                continue
            }
            trade.isDirty = false
            trade.isDeleted = false
            trade.tradeDetails = trade.tradeDetails.map { d in
                var copy = d
                copy.isDirty = false
                copy.isDeleted = false
                return copy
            }
            detailCount += trade.tradeDetails.count
            db.saveTrade(trade)
        }

        for var plan in snapshot.plans {
            if mode == .merge, let local = existingPlans[plan.documentId], local.isDirty && local.updatedAt > plan.updatedAt {
                continue
            }
            plan.isDirty = false
            plan.isDeleted = false
            db.savePlan(plan)
        }

        for var roadmap in snapshot.roadmaps {
            if mode == .merge, let local = existingRoadmaps[roadmap.documentId], local.isDirty && local.updatedAt > roadmap.updatedAt {
                continue
            }
            roadmap.isDirty = false
            roadmap.isDeleted = false
            db.saveRoadmap(roadmap)
        }

        // Apply deletions if any
        for delId in snapshot.deletedTradeDocumentIds ?? [] {
            db.executeRaw("UPDATE trades SET is_deleted = 1, is_dirty = 0 WHERE document_id = '\(delId)';")
        }
        for delId in snapshot.deletedPlanDocumentIds ?? [] {
            db.executeRaw("UPDATE plans SET is_deleted = 1, is_dirty = 0 WHERE document_id = '\(delId)';")
        }
        for delId in snapshot.deletedRoadmapDocumentIds ?? [] {
            db.executeRaw("UPDATE roadmaps SET is_deleted = 1, is_dirty = 0 WHERE document_id = '\(delId)';")
        }

        return SyncImportSummary(
            accountsCount: snapshot.accounts.count,
            symbolsCount: snapshot.symbols.count,
            strategiesCount: snapshot.strategies.count,
            tradesCount: snapshot.trades.count,
            tradeDetailsCount: detailCount,
            plansCount: snapshot.plans.count,
            roadmapsCount: snapshot.roadmaps.count,
            sourceDevice: snapshot.sourceDevice,
            exportedAt: snapshot.exportedAt
        )
    }
}

