-- ============================================================================
-- TradingJournal Mini (iOS / iPhone) - Local SQLite Schema
-- Designed for 2-way JSON Snapshot & Strapi v5 Sync with Desktop (PostgreSQL)
-- ============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- 1. Metadata & Sync State
CREATE TABLE IF NOT EXISTS sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 2. Markets (VNStock, Derivative, Crypto, Global...)
CREATE TABLE IF NOT EXISTS markets (
    document_id TEXT PRIMARY KEY,
    raw_id INTEGER,
    name TEXT NOT NULL,
    description TEXT,
    updated_at TEXT NOT NULL,
    is_dirty INTEGER NOT NULL DEFAULT 0
);

-- 3. Risk Settings (1-1 with Account)
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

-- 4. Strategies (Read/Select for Trades & Accounts; managed on Desktop)
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

-- 5. Accounts
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
    setting_document_id TEXT,
    strategy_document_id TEXT,
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
    is_dirty INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (market_document_id) REFERENCES markets(document_id) ON DELETE SET NULL,
    FOREIGN KEY (setting_document_id) REFERENCES settings(document_id) ON DELETE SET NULL,
    FOREIGN KEY (strategy_document_id) REFERENCES strategies(document_id) ON DELETE SET NULL
);

-- 6. Symbols (Ticker catalog + latest cached price for Today Portfolio / Station)
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

-- 7. Trades (Core Journal table)
CREATE TABLE IF NOT EXISTS trades (
    document_id TEXT PRIMARY KEY,
    raw_id INTEGER,
    type TEXT NOT NULL CHECK (type IN ('Long', 'Short')),
    trade_status TEXT NOT NULL DEFAULT 'Open' CHECK (trade_status IN ('Open', 'Closed', 'ScaleIn', 'ScaleOut')),
    note TEXT,
    date TEXT NOT NULL,
    account_document_id TEXT NOT NULL,
    symbol_document_id TEXT,
    symbol_name_snapshot TEXT,
    strategy_document_id TEXT,
    scored INTEGER NOT NULL DEFAULT 0,
    pnl REAL,
    forward_test INTEGER NOT NULL DEFAULT 0,
    backtest INTEGER NOT NULL DEFAULT 0,
    market_snapshot_json TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    is_dirty INTEGER NOT NULL DEFAULT 0,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (account_document_id) REFERENCES accounts(document_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_trades_account ON trades(account_document_id);
CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(trade_status);
CREATE INDEX IF NOT EXISTS idx_trades_date ON trades(date);

-- 8. Trade Details (Individual Buy/Sell executions: Entry, TakeProfit, Stoploss, Exit)
CREATE TABLE IF NOT EXISTS trade_details (
    document_id TEXT PRIMARY KEY,
    raw_id INTEGER,
    trade_document_id TEXT NOT NULL,
    price REAL NOT NULL DEFAULT 0,
    type TEXT NOT NULL CHECK (type IN ('Buy', 'Sell')),
    volume REAL NOT NULL DEFAULT 0,
    signal TEXT NOT NULL DEFAULT 'Entry' CHECK (signal IN ('Entry', 'TakeProfit', 'Stoploss', 'Exit')),
    date TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    is_dirty INTEGER NOT NULL DEFAULT 0,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (trade_document_id) REFERENCES trades(document_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_trade_details_trade ON trade_details(trade_document_id);
CREATE INDEX IF NOT EXISTS idx_trade_details_date ON trade_details(date);

-- 9. Plans (Daily & Weekly Trading Plans)
CREATE TABLE IF NOT EXISTS plans (
    document_id TEXT PRIMARY KEY,
    raw_id INTEGER,
    account_id TEXT NOT NULL,
    account_name TEXT NOT NULL,
    title TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT 'Daily' CHECK (scope IN ('Daily', 'Weekly')),
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
    status TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'Active', 'Done', 'Skipped')),
    max_trades INTEGER NOT NULL DEFAULT 3,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    is_dirty INTEGER NOT NULL DEFAULT 0,
    is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_plans_account ON plans(account_id);
CREATE INDEX IF NOT EXISTS idx_plans_date ON plans(plan_date);

-- 10. Roadmaps (Account Growth Targets & Compounding Milestones)
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
    status TEXT NOT NULL DEFAULT 'unprocess' CHECK (status IN ('unprocess', 'process', 'completed')),
    target_balance REAL,
    profit_target REAL,
    win_rate_estimate REAL DEFAULT 50.0,
    snapshot_json TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    is_dirty INTEGER NOT NULL DEFAULT 0,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (account_document_id) REFERENCES accounts(document_id) ON DELETE CASCADE
);

-- 11. Allocation Snapshots (Saved Asset Allocation Configurations)
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

