import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Lightweight, zero-dependency SQLite3 database manager for iOS that mirrors the Desktop Strapi v5 PostgreSQL schema.
final class SQLiteDatabase {
    static let shared = SQLiteDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tradingjournal.mini.sqlite", qos: .userInitiated)
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let fallbackIsoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    let databasePath: String

    init(customPath: String? = nil) {
        if let customPath = customPath {
            self.databasePath = customPath
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.databasePath = docs.appendingPathComponent("trading_journal_mini.sqlite").path
        }
        openDatabase()
        createSchema()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        if sqlite3_open(databasePath, &db) != SQLITE_OK {
            print("[SQLiteDatabase] Failed to open SQLite database at \(databasePath)")
        } else {
            executeRaw("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
        }
    }

    func executeRaw(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("[SQLiteDatabase] SQL Error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    func createSchema() {
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS markets (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            name TEXT NOT NULL,
            description TEXT,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS settings (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            name TEXT,
            risk_per_trade REAL DEFAULT 1.0,
            max_draw_down REAL DEFAULT 10.0,
            capital_risk REAL DEFAULT 10.0,
            account_document_id TEXT,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS strategies (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            name TEXT NOT NULL,
            description TEXT,
            type TEXT DEFAULT 'Rules',
            strategy_file TEXT,
            template TEXT,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS accounts (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            name TEXT NOT NULL,
            description TEXT,
            initial_balance REAL NOT NULL DEFAULT 0,
            cash REAL DEFAULT 0,
            margin REAL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'VND',
            market_document_id TEXT,
            market_name TEXT,
            setting_document_id TEXT,
            strategy_document_id TEXT,
            strategy_name TEXT,
            volume_format TEXT,
            money_format TEXT,
            fee_rate REAL,
            sell_tax_rate REAL,
            fee_per_contract REAL,
            max_position_pct REAL,
            max_average_down INTEGER,
            timeframe TEXT,
            allocation_json TEXT,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS symbols (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            name TEXT NOT NULL UNIQUE,
            description TEXT,
            exchange TEXT,
            short_name TEXT,
            industry TEXT,
            sector TEXT,
            market_document_id TEXT,
            last_close REAL,
            prev_close REAL,
            last_volume REAL,
            avg_volume_20d REAL,
            ma20 REAL,
            last_price_date TEXT,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS trades (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            type TEXT NOT NULL,
            trade_status TEXT NOT NULL DEFAULT 'Open',
            note TEXT,
            date TEXT NOT NULL,
            account_document_id TEXT NOT NULL,
            symbol_document_id TEXT,
            symbol_name_snapshot TEXT NOT NULL,
            strategy_document_id TEXT,
            strategy_name_snapshot TEXT,
            scored INTEGER NOT NULL DEFAULT 0,
            pnl REAL,
            forward_test INTEGER NOT NULL DEFAULT 0,
            backtest INTEGER NOT NULL DEFAULT 0,
            market_snapshot_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS trade_details (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            trade_document_id TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0,
            type TEXT NOT NULL,
            volume REAL NOT NULL DEFAULT 0,
            signal TEXT NOT NULL DEFAULT 'Entry',
            date TEXT NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS plans (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            account_id TEXT NOT NULL,
            account_name TEXT NOT NULL,
            title TEXT NOT NULL,
            scope TEXT NOT NULL DEFAULT 'Daily',
            plan_date TEXT,
            week_start TEXT,
            week_end TEXT,
            session TEXT,
            market_context TEXT,
            symbols TEXT,
            entry_plan TEXT,
            risk_plan TEXT,
            checklist TEXT,
            review_notes TEXT,
            status TEXT NOT NULL DEFAULT 'Draft',
            max_trades INTEGER NOT NULL DEFAULT 3,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS roadmaps (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            account_document_id TEXT NOT NULL,
            setting_document_id TEXT,
            starting_balance REAL NOT NULL DEFAULT 0,
            target_growth_percent REAL NOT NULL DEFAULT 25,
            planned_trades INTEGER NOT NULL DEFAULT 25,
            risk_percent REAL DEFAULT 1.0,
            reward_multiple REAL DEFAULT 2.0,
            max_draw_down_percent REAL DEFAULT 10.0,
            status TEXT NOT NULL DEFAULT 'unprocess',
            target_balance REAL,
            profit_target REAL,
            win_rate_estimate REAL DEFAULT 50.0,
            snapshot_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS allocation_snapshots (
            document_id TEXT PRIMARY KEY,
            raw_id INTEGER,
            name TEXT NOT NULL,
            from_date TEXT,
            to_date TEXT,
            accounts_json TEXT,
            settings_json TEXT,
            updated_at TEXT NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
        );
        """
        executeRaw(schemaSQL)
    }

    // MARK: - Date Helpers

    func formatDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    func parseDate(_ str: String?) -> Date {
        guard let str = str, !str.isEmpty else { return Date() }
        if let d = isoFormatter.date(from: str) { return d }
        if let d = fallbackIsoFormatter.date(from: str) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: String(str.prefix(10))) { return d }
        return Date()
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func columnDoubleOpt(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func columnIntOpt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindDoubleOpt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value = value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindIntOpt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int64(stmt, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    // MARK: - Upsert & Fetch Operations

    func saveSetting(_ item: RiskSetting) {
        let sql = """
        INSERT INTO settings (document_id, raw_id, name, risk_per_trade, max_draw_down, capital_risk, account_document_id, updated_at, is_dirty)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id,
            name=excluded.name,
            risk_per_trade=excluded.risk_per_trade,
            max_draw_down=excluded.max_draw_down,
            capital_risk=excluded.capital_risk,
            account_document_id=excluded.account_document_id,
            updated_at=excluded.updated_at,
            is_dirty=excluded.is_dirty;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, item.documentId)
            bindIntOpt(stmt, 2, item.rawId)
            bindText(stmt, 3, item.name)
            sqlite3_bind_double(stmt, 4, item.riskPerTrade)
            sqlite3_bind_double(stmt, 5, item.maxDrawDown)
            sqlite3_bind_double(stmt, 6, item.capitalRisk)
            bindText(stmt, 7, item.accountDocumentId)
            bindText(stmt, 8, formatDate(item.updatedAt))
            sqlite3_bind_int(stmt, 9, item.isDirty ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchSettings() -> [RiskSetting] {
        var result: [RiskSetting] = []
        let sql = "SELECT document_id, raw_id, name, risk_per_trade, max_draw_down, capital_risk, account_document_id, updated_at, is_dirty FROM settings;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(RiskSetting(
                    documentId: columnText(stmt, 0) ?? UUID().uuidString,
                    rawId: columnIntOpt(stmt, 1),
                    name: columnText(stmt, 2) ?? "Default Risk",
                    riskPerTrade: sqlite3_column_double(stmt, 3),
                    maxDrawDown: sqlite3_column_double(stmt, 4),
                    capitalRisk: sqlite3_column_double(stmt, 5),
                    accountDocumentId: columnText(stmt, 6),
                    updatedAt: parseDate(columnText(stmt, 7)),
                    isDirty: sqlite3_column_int(stmt, 8) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func saveAccount(_ item: Account) {
        if let setting = item.setting {
            saveSetting(setting)
        }
        let sql = """
        INSERT INTO accounts (
            document_id, raw_id, name, description, initial_balance, cash, margin, currency,
            market_document_id, market_name, setting_document_id, strategy_document_id, strategy_name,
            volume_format, money_format, fee_rate, sell_tax_rate, fee_per_contract, max_position_pct,
            max_average_down, timeframe, allocation_json, updated_at, is_dirty
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, name=excluded.name, description=excluded.description,
            initial_balance=excluded.initial_balance, cash=excluded.cash, margin=excluded.margin,
            currency=excluded.currency, market_document_id=excluded.market_document_id,
            market_name=excluded.market_name, setting_document_id=excluded.setting_document_id,
            strategy_document_id=excluded.strategy_document_id, strategy_name=excluded.strategy_name,
            volume_format=excluded.volume_format, money_format=excluded.money_format,
            fee_rate=excluded.fee_rate, sell_tax_rate=excluded.sell_tax_rate,
            fee_per_contract=excluded.fee_per_contract, max_position_pct=excluded.max_position_pct,
            max_average_down=excluded.max_average_down, timeframe=excluded.timeframe,
            allocation_json=excluded.allocation_json, updated_at=excluded.updated_at, is_dirty=excluded.is_dirty;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, item.documentId)
            bindIntOpt(stmt, 2, item.rawId)
            bindText(stmt, 3, item.name)
            bindText(stmt, 4, item.description)
            sqlite3_bind_double(stmt, 5, item.initialBalance)
            bindDoubleOpt(stmt, 6, item.cash)
            bindDoubleOpt(stmt, 7, item.margin)
            bindText(stmt, 8, item.currency)
            bindText(stmt, 9, item.marketDocumentId)
            bindText(stmt, 10, item.marketName)
            bindText(stmt, 11, item.setting?.documentId ?? item.settingDocumentId)
            bindText(stmt, 12, item.strategyDocumentId)
            bindText(stmt, 13, item.strategyName)
            bindText(stmt, 14, item.volumeFormat)
            bindText(stmt, 15, item.moneyFormat)
            bindDoubleOpt(stmt, 16, item.feeRate)
            bindDoubleOpt(stmt, 17, item.sellTaxRate)
            bindDoubleOpt(stmt, 18, item.feePerContract)
            bindDoubleOpt(stmt, 19, item.maxPositionPct)
            bindIntOpt(stmt, 20, item.maxAverageDown)
            bindText(stmt, 21, item.timeframe)
            bindText(stmt, 22, item.allocationJson)
            bindText(stmt, 23, formatDate(item.updatedAt))
            sqlite3_bind_int(stmt, 24, item.isDirty ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchAccounts() -> [Account] {
        let settingsById = Dictionary(uniqueKeysWithValues: fetchSettings().map { ($0.documentId, $0) })
        var result: [Account] = []
        let sql = """
        SELECT document_id, raw_id, name, description, initial_balance, cash, margin, currency,
               market_document_id, market_name, setting_document_id, strategy_document_id, strategy_name,
               volume_format, money_format, fee_rate, sell_tax_rate, fee_per_contract, max_position_pct,
               max_average_down, timeframe, allocation_json, updated_at, is_dirty
        FROM accounts ORDER BY name ASC;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let docId = columnText(stmt, 0) ?? UUID().uuidString
                let settingId = columnText(stmt, 10)
                let matchedSetting = settingId.flatMap { settingsById[$0] }
                    ?? settingsById.values.first(where: { $0.accountDocumentId == docId })
                result.append(Account(
                    documentId: docId,
                    rawId: columnIntOpt(stmt, 1),
                    name: columnText(stmt, 2) ?? "Account",
                    description: columnText(stmt, 3),
                    initialBalance: sqlite3_column_double(stmt, 4),
                    cash: columnDoubleOpt(stmt, 5),
                    margin: columnDoubleOpt(stmt, 6),
                    currency: columnText(stmt, 7) ?? "VND",
                    marketDocumentId: columnText(stmt, 8),
                    marketName: columnText(stmt, 9),
                    settingDocumentId: settingId,
                    setting: matchedSetting,
                    strategyDocumentId: columnText(stmt, 11),
                    strategyName: columnText(stmt, 12),
                    volumeFormat: columnText(stmt, 13),
                    moneyFormat: columnText(stmt, 14),
                    feeRate: columnDoubleOpt(stmt, 15),
                    sellTaxRate: columnDoubleOpt(stmt, 16),
                    feePerContract: columnDoubleOpt(stmt, 17),
                    maxPositionPct: columnDoubleOpt(stmt, 18),
                    maxAverageDown: columnIntOpt(stmt, 19),
                    timeframe: columnText(stmt, 20),
                    allocationJson: columnText(stmt, 21),
                    updatedAt: parseDate(columnText(stmt, 22)),
                    isDirty: sqlite3_column_int(stmt, 23) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func saveSymbol(_ item: SymbolItem) {
        let sql = """
        INSERT INTO symbols (
            document_id, raw_id, name, description, exchange, short_name, industry, sector,
            market_document_id, last_close, prev_close, last_volume, avg_volume_20d, ma20,
            last_price_date, updated_at, is_dirty
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, name=excluded.name, description=excluded.description,
            exchange=excluded.exchange, short_name=excluded.short_name, industry=excluded.industry,
            sector=excluded.sector, market_document_id=excluded.market_document_id,
            last_close=excluded.last_close, prev_close=excluded.prev_close,
            last_volume=excluded.last_volume, avg_volume_20d=excluded.avg_volume_20d,
            ma20=excluded.ma20, last_price_date=excluded.last_price_date,
            updated_at=excluded.updated_at, is_dirty=excluded.is_dirty;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, item.documentId)
            bindIntOpt(stmt, 2, item.rawId)
            bindText(stmt, 3, item.name.uppercased())
            bindText(stmt, 4, item.description)
            bindText(stmt, 5, item.exchange)
            bindText(stmt, 6, item.shortName)
            bindText(stmt, 7, item.industry)
            bindText(stmt, 8, item.sector)
            bindText(stmt, 9, item.marketDocumentId)
            bindDoubleOpt(stmt, 10, item.lastClose)
            bindDoubleOpt(stmt, 11, item.prevClose)
            bindDoubleOpt(stmt, 12, item.lastVolume)
            bindDoubleOpt(stmt, 13, item.avgVolume20d)
            bindDoubleOpt(stmt, 14, item.ma20)
            bindText(stmt, 15, item.lastPriceDate)
            bindText(stmt, 16, formatDate(item.updatedAt))
            sqlite3_bind_int(stmt, 17, item.isDirty ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchSymbols() -> [SymbolItem] {
        var result: [SymbolItem] = []
        let sql = """
        SELECT document_id, raw_id, name, description, exchange, short_name, industry, sector,
               market_document_id, last_close, prev_close, last_volume, avg_volume_20d, ma20,
               last_price_date, updated_at, is_dirty
        FROM symbols ORDER BY name ASC;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(SymbolItem(
                    documentId: columnText(stmt, 0) ?? UUID().uuidString,
                    rawId: columnIntOpt(stmt, 1),
                    name: columnText(stmt, 2) ?? "",
                    description: columnText(stmt, 3),
                    exchange: columnText(stmt, 4),
                    shortName: columnText(stmt, 5),
                    industry: columnText(stmt, 6),
                    sector: columnText(stmt, 7),
                    marketDocumentId: columnText(stmt, 8),
                    lastClose: columnDoubleOpt(stmt, 9),
                    prevClose: columnDoubleOpt(stmt, 10),
                    lastVolume: columnDoubleOpt(stmt, 11),
                    avgVolume20d: columnDoubleOpt(stmt, 12),
                    ma20: columnDoubleOpt(stmt, 13),
                    lastPriceDate: columnText(stmt, 14),
                    updatedAt: parseDate(columnText(stmt, 15)),
                    isDirty: sqlite3_column_int(stmt, 16) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func saveStrategy(_ item: StrategyItem) {
        let sql = """
        INSERT INTO strategies (document_id, raw_id, name, description, type, strategy_file, template, updated_at, is_dirty)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, name=excluded.name, description=excluded.description,
            type=excluded.type, strategy_file=excluded.strategy_file, template=excluded.template,
            updated_at=excluded.updated_at, is_dirty=excluded.is_dirty;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, item.documentId)
            bindIntOpt(stmt, 2, item.rawId)
            bindText(stmt, 3, item.name)
            bindText(stmt, 4, item.description)
            bindText(stmt, 5, item.type)
            bindText(stmt, 6, item.strategyFile)
            bindText(stmt, 7, item.template)
            bindText(stmt, 8, formatDate(item.updatedAt))
            sqlite3_bind_int(stmt, 9, item.isDirty ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchStrategies() -> [StrategyItem] {
        var result: [StrategyItem] = []
        let sql = "SELECT document_id, raw_id, name, description, type, strategy_file, template, updated_at, is_dirty FROM strategies ORDER BY name ASC;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(StrategyItem(
                    documentId: columnText(stmt, 0) ?? UUID().uuidString,
                    rawId: columnIntOpt(stmt, 1),
                    name: columnText(stmt, 2) ?? "",
                    description: columnText(stmt, 3),
                    type: columnText(stmt, 4) ?? "Rules",
                    strategyFile: columnText(stmt, 5),
                    template: columnText(stmt, 6),
                    updatedAt: parseDate(columnText(stmt, 7)),
                    isDirty: sqlite3_column_int(stmt, 8) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func saveTradeDetail(_ detail: TradeDetail) {
        let sql = """
        INSERT INTO trade_details (
            document_id, raw_id, trade_document_id, price, type, volume, signal, date, note,
            created_at, updated_at, is_dirty, is_deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, trade_document_id=excluded.trade_document_id,
            price=excluded.price, type=excluded.type, volume=excluded.volume,
            signal=excluded.signal, date=excluded.date, note=excluded.note,
            updated_at=excluded.updated_at, is_dirty=excluded.is_dirty, is_deleted=excluded.is_deleted;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, detail.documentId)
            bindIntOpt(stmt, 2, detail.rawId)
            bindText(stmt, 3, detail.tradeDocumentId)
            sqlite3_bind_double(stmt, 4, detail.price)
            bindText(stmt, 5, detail.type.rawValue)
            sqlite3_bind_double(stmt, 6, detail.volume)
            bindText(stmt, 7, detail.signal.rawValue)
            bindText(stmt, 8, formatDate(detail.date))
            bindText(stmt, 9, detail.note)
            bindText(stmt, 10, formatDate(detail.createdAt))
            bindText(stmt, 11, formatDate(detail.updatedAt))
            sqlite3_bind_int(stmt, 12, detail.isDirty ? 1 : 0)
            sqlite3_bind_int(stmt, 13, detail.isDeleted ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func saveTrade(_ trade: Trade) {
        let sql = """
        INSERT INTO trades (
            document_id, raw_id, type, trade_status, note, date, account_document_id,
            symbol_document_id, symbol_name_snapshot, strategy_document_id, strategy_name_snapshot,
            scored, pnl, forward_test, backtest, market_snapshot_json,
            created_at, updated_at, is_dirty, is_deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, type=excluded.type, trade_status=excluded.trade_status,
            note=excluded.note, date=excluded.date, account_document_id=excluded.account_document_id,
            symbol_document_id=excluded.symbol_document_id, symbol_name_snapshot=excluded.symbol_name_snapshot,
            strategy_document_id=excluded.strategy_document_id, strategy_name_snapshot=excluded.strategy_name_snapshot,
            scored=excluded.scored, pnl=excluded.pnl, forward_test=excluded.forward_test,
            backtest=excluded.backtest, market_snapshot_json=excluded.market_snapshot_json,
            updated_at=excluded.updated_at, is_dirty=excluded.is_dirty, is_deleted=excluded.is_deleted;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, trade.documentId)
            bindIntOpt(stmt, 2, trade.rawId)
            bindText(stmt, 3, trade.type.rawValue)
            bindText(stmt, 4, trade.tradeStatus.rawValue)
            bindText(stmt, 5, trade.note)
            bindText(stmt, 6, formatDate(trade.date))
            bindText(stmt, 7, trade.accountDocumentId)
            bindText(stmt, 8, trade.symbolDocumentId)
            bindText(stmt, 9, trade.symbolName.uppercased())
            bindText(stmt, 10, trade.strategyDocumentId)
            bindText(stmt, 11, trade.strategyName)
            sqlite3_bind_int(stmt, 12, Int32(trade.scored))
            bindDoubleOpt(stmt, 13, trade.pnl)
            sqlite3_bind_int(stmt, 14, trade.forwardTest ? 1 : 0)
            sqlite3_bind_int(stmt, 15, trade.backtest ? 1 : 0)
            bindText(stmt, 16, trade.marketSnapshotJson)
            bindText(stmt, 17, formatDate(trade.createdAt))
            bindText(stmt, 18, formatDate(trade.updatedAt))
            sqlite3_bind_int(stmt, 19, trade.isDirty ? 1 : 0)
            sqlite3_bind_int(stmt, 20, trade.isDeleted ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        for detail in trade.tradeDetails {
            saveTradeDetail(detail)
        }
    }

    func fetchTrades(includeDeleted: Bool = false) -> [Trade] {
        var detailsByTrade: [String: [TradeDetail]] = [:]
        let detailSQL = """
        SELECT document_id, raw_id, trade_document_id, price, type, volume, signal, date, note,
               created_at, updated_at, is_dirty, is_deleted
        FROM trade_details
        \(includeDeleted ? "" : "WHERE is_deleted = 0")
        ORDER BY date ASC;
        """
        var dStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, detailSQL, -1, &dStmt, nil) == SQLITE_OK {
            while sqlite3_step(dStmt) == SQLITE_ROW {
                let tradeId = columnText(dStmt, 2) ?? ""
                let detail = TradeDetail(
                    documentId: columnText(dStmt, 0) ?? UUID().uuidString,
                    rawId: columnIntOpt(dStmt, 1),
                    tradeDocumentId: tradeId,
                    price: sqlite3_column_double(dStmt, 3),
                    type: OrderSide(rawValue: columnText(dStmt, 4) ?? "Buy") ?? .buy,
                    volume: sqlite3_column_double(dStmt, 5),
                    signal: TradeSignalType(rawValue: columnText(dStmt, 6) ?? "Entry") ?? .entry,
                    date: parseDate(columnText(dStmt, 7)),
                    note: columnText(dStmt, 8) ?? "",
                    createdAt: parseDate(columnText(dStmt, 9)),
                    updatedAt: parseDate(columnText(dStmt, 10)),
                    isDirty: sqlite3_column_int(dStmt, 11) != 0,
                    isDeleted: sqlite3_column_int(dStmt, 12) != 0
                )
                detailsByTrade[tradeId, default: []].append(detail)
            }
        }
        sqlite3_finalize(dStmt)

        var trades: [Trade] = []
        let tradeSQL = """
        SELECT document_id, raw_id, type, trade_status, note, date, account_document_id,
               symbol_document_id, symbol_name_snapshot, strategy_document_id, strategy_name_snapshot,
               scored, pnl, forward_test, backtest, market_snapshot_json,
               created_at, updated_at, is_dirty, is_deleted
        FROM trades
        \(includeDeleted ? "" : "WHERE is_deleted = 0")
        ORDER BY date DESC;
        """
        var tStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, tradeSQL, -1, &tStmt, nil) == SQLITE_OK {
            while sqlite3_step(tStmt) == SQLITE_ROW {
                let docId = columnText(tStmt, 0) ?? UUID().uuidString
                trades.append(Trade(
                    documentId: docId,
                    rawId: columnIntOpt(tStmt, 1),
                    type: TradeDirection(rawValue: columnText(tStmt, 2) ?? "Long") ?? .long,
                    tradeStatus: TradeStatus(rawValue: columnText(tStmt, 3) ?? "Open") ?? .open,
                    note: columnText(tStmt, 4) ?? "",
                    date: parseDate(columnText(tStmt, 5)),
                    accountDocumentId: columnText(tStmt, 6) ?? "",
                    symbolDocumentId: columnText(tStmt, 7),
                    symbolName: columnText(tStmt, 8) ?? "",
                    strategyDocumentId: columnText(tStmt, 9),
                    strategyName: columnText(tStmt, 10),
                    scored: Int(sqlite3_column_int(tStmt, 11)),
                    pnl: columnDoubleOpt(tStmt, 12),
                    forwardTest: sqlite3_column_int(tStmt, 13) != 0,
                    backtest: sqlite3_column_int(tStmt, 14) != 0,
                    marketSnapshotJson: columnText(tStmt, 15),
                    tradeDetails: detailsByTrade[docId] ?? [],
                    createdAt: parseDate(columnText(tStmt, 16)),
                    updatedAt: parseDate(columnText(tStmt, 17)),
                    isDirty: sqlite3_column_int(tStmt, 18) != 0,
                    isDeleted: sqlite3_column_int(tStmt, 19) != 0
                ))
            }
        }
        sqlite3_finalize(tStmt)
        return trades
    }

    func savePlan(_ plan: TradingPlan) {
        let sql = """
        INSERT INTO plans (
            document_id, raw_id, account_id, account_name, title, scope, plan_date, week_start, week_end,
            session, market_context, symbols, entry_plan, risk_plan, checklist, review_notes,
            status, max_trades, created_at, updated_at, is_dirty, is_deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, account_id=excluded.account_id, account_name=excluded.account_name,
            title=excluded.title, scope=excluded.scope, plan_date=excluded.plan_date,
            week_start=excluded.week_start, week_end=excluded.week_end, session=excluded.session,
            market_context=excluded.market_context, symbols=excluded.symbols, entry_plan=excluded.entry_plan,
            risk_plan=excluded.risk_plan, checklist=excluded.checklist, review_notes=excluded.review_notes,
            status=excluded.status, max_trades=excluded.max_trades, updated_at=excluded.updated_at,
            is_dirty=excluded.is_dirty, is_deleted=excluded.is_deleted;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, plan.documentId)
            bindIntOpt(stmt, 2, plan.rawId)
            bindText(stmt, 3, plan.accountId)
            bindText(stmt, 4, plan.accountName)
            bindText(stmt, 5, plan.title)
            bindText(stmt, 6, plan.scope.rawValue)
            bindText(stmt, 7, plan.planDate)
            bindText(stmt, 8, plan.weekStart)
            bindText(stmt, 9, plan.weekEnd)
            bindText(stmt, 10, plan.session)
            bindText(stmt, 11, plan.marketContext)
            bindText(stmt, 12, plan.symbols)
            bindText(stmt, 13, plan.entryPlan)
            bindText(stmt, 14, plan.riskPlan)
            bindText(stmt, 15, plan.checklist)
            bindText(stmt, 16, plan.reviewNotes)
            bindText(stmt, 17, plan.status.rawValue)
            sqlite3_bind_int(stmt, 18, Int32(plan.maxTrades))
            bindText(stmt, 19, formatDate(plan.createdAt))
            bindText(stmt, 20, formatDate(plan.updatedAt))
            sqlite3_bind_int(stmt, 21, plan.isDirty ? 1 : 0)
            sqlite3_bind_int(stmt, 22, plan.isDeleted ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchPlans(includeDeleted: Bool = false) -> [TradingPlan] {
        var result: [TradingPlan] = []
        let sql = """
        SELECT document_id, raw_id, account_id, account_name, title, scope, plan_date, week_start, week_end,
               session, market_context, symbols, entry_plan, risk_plan, checklist, review_notes,
               status, max_trades, created_at, updated_at, is_dirty, is_deleted
        FROM plans
        \(includeDeleted ? "" : "WHERE is_deleted = 0")
        ORDER BY updated_at DESC;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(TradingPlan(
                    documentId: columnText(stmt, 0) ?? UUID().uuidString,
                    rawId: columnIntOpt(stmt, 1),
                    accountId: columnText(stmt, 2) ?? "",
                    accountName: columnText(stmt, 3) ?? "",
                    title: columnText(stmt, 4) ?? "",
                    scope: PlanScope(rawValue: columnText(stmt, 5) ?? "Daily") ?? .daily,
                    planDate: columnText(stmt, 6),
                    weekStart: columnText(stmt, 7),
                    weekEnd: columnText(stmt, 8),
                    session: columnText(stmt, 9),
                    marketContext: columnText(stmt, 10) ?? "",
                    symbols: columnText(stmt, 11) ?? "",
                    entryPlan: columnText(stmt, 12) ?? "",
                    riskPlan: columnText(stmt, 13) ?? "",
                    checklist: columnText(stmt, 14) ?? "",
                    reviewNotes: columnText(stmt, 15) ?? "",
                    status: PlanStatus(rawValue: columnText(stmt, 16) ?? "Draft") ?? .draft,
                    maxTrades: Int(sqlite3_column_int(stmt, 17)),
                    createdAt: parseDate(columnText(stmt, 18)),
                    updatedAt: parseDate(columnText(stmt, 19)),
                    isDirty: sqlite3_column_int(stmt, 20) != 0,
                    isDeleted: sqlite3_column_int(stmt, 21) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func saveRoadmap(_ item: RoadmapItem) {
        let sql = """
        INSERT INTO roadmaps (
            document_id, raw_id, account_document_id, setting_document_id, starting_balance,
            target_growth_percent, planned_trades, risk_percent, reward_multiple, max_draw_down_percent,
            status, target_balance, profit_target, win_rate_estimate, snapshot_json,
            created_at, updated_at, is_dirty, is_deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            raw_id=excluded.raw_id, account_document_id=excluded.account_document_id,
            setting_document_id=excluded.setting_document_id, starting_balance=excluded.starting_balance,
            target_growth_percent=excluded.target_growth_percent, planned_trades=excluded.planned_trades,
            risk_percent=excluded.risk_percent, reward_multiple=excluded.reward_multiple,
            max_draw_down_percent=excluded.max_draw_down_percent, status=excluded.status,
            target_balance=excluded.target_balance, profit_target=excluded.profit_target,
            win_rate_estimate=excluded.win_rate_estimate, snapshot_json=excluded.snapshot_json,
            updated_at=excluded.updated_at, is_dirty=excluded.is_dirty, is_deleted=excluded.is_deleted;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, item.documentId)
            bindIntOpt(stmt, 2, item.rawId)
            bindText(stmt, 3, item.accountDocumentId)
            bindText(stmt, 4, item.settingDocumentId)
            sqlite3_bind_double(stmt, 5, item.startingBalance)
            sqlite3_bind_double(stmt, 6, item.targetGrowthPercent)
            sqlite3_bind_int(stmt, 7, Int32(item.plannedTrades))
            sqlite3_bind_double(stmt, 8, item.riskPercent)
            sqlite3_bind_double(stmt, 9, item.rewardMultiple)
            sqlite3_bind_double(stmt, 10, item.maxDrawDownPercent)
            bindText(stmt, 11, item.status.rawValue)
            sqlite3_bind_double(stmt, 12, item.targetBalance)
            sqlite3_bind_double(stmt, 13, item.profitTarget)
            sqlite3_bind_double(stmt, 14, item.winRateEstimate)
            bindText(stmt, 15, item.snapshotJson)
            bindText(stmt, 16, formatDate(item.createdAt))
            bindText(stmt, 17, formatDate(item.updatedAt))
            sqlite3_bind_int(stmt, 18, item.isDirty ? 1 : 0)
            sqlite3_bind_int(stmt, 19, item.isDeleted ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchRoadmaps(includeDeleted: Bool = false) -> [RoadmapItem] {
        var result: [RoadmapItem] = []
        let sql = """
        SELECT document_id, raw_id, account_document_id, setting_document_id, starting_balance,
               target_growth_percent, planned_trades, risk_percent, reward_multiple, max_draw_down_percent,
               status, target_balance, profit_target, win_rate_estimate, snapshot_json,
               created_at, updated_at, is_dirty, is_deleted
        FROM roadmaps
        \(includeDeleted ? "" : "WHERE is_deleted = 0")
        ORDER BY created_at DESC;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(RoadmapItem(
                    documentId: columnText(stmt, 0) ?? UUID().uuidString,
                    rawId: columnIntOpt(stmt, 1),
                    accountDocumentId: columnText(stmt, 2) ?? "",
                    settingDocumentId: columnText(stmt, 3),
                    startingBalance: sqlite3_column_double(stmt, 4),
                    targetGrowthPercent: sqlite3_column_double(stmt, 5),
                    plannedTrades: Int(sqlite3_column_int(stmt, 6)),
                    riskPercent: sqlite3_column_double(stmt, 7),
                    rewardMultiple: sqlite3_column_double(stmt, 8),
                    maxDrawDownPercent: sqlite3_column_double(stmt, 9),
                    status: RoadmapStatus(rawValue: columnText(stmt, 10) ?? "unprocess") ?? .unprocess,
                    targetBalance: sqlite3_column_double(stmt, 11),
                    profitTarget: sqlite3_column_double(stmt, 12),
                    winRateEstimate: sqlite3_column_double(stmt, 13),
                    snapshotJson: columnText(stmt, 14),
                    createdAt: parseDate(columnText(stmt, 15)),
                    updatedAt: parseDate(columnText(stmt, 16)),
                    isDirty: sqlite3_column_int(stmt, 17) != 0,
                    isDeleted: sqlite3_column_int(stmt, 18) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func markAllSynced() {
        executeRaw("""
        UPDATE accounts SET is_dirty = 0;
        UPDATE settings SET is_dirty = 0;
        UPDATE symbols SET is_dirty = 0;
        UPDATE strategies SET is_dirty = 0;
        UPDATE trades SET is_dirty = 0;
        UPDATE trade_details SET is_dirty = 0;
        UPDATE plans SET is_dirty = 0;
        UPDATE roadmaps SET is_dirty = 0;
        """)
    }

    func clearAllData() {
        executeRaw("""
        DELETE FROM trade_details;
        DELETE FROM trades;
        DELETE FROM plans;
        DELETE FROM roadmaps;
        DELETE FROM allocation_snapshots;
        DELETE FROM symbols;
        DELETE FROM accounts;
        DELETE FROM settings;
        DELETE FROM strategies;
        DELETE FROM markets;
        """)
    }
}

