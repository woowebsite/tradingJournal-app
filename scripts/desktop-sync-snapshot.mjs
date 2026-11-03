#!/usr/bin/env node
/**
 * Desktop <-> iPhone JSON Sync Snapshot Utility
 * Synchronizes data between Desktop Strapi v5 (D:\PROGRAMMING\MyGithub\tradingJournal)
 * and the iOS SwiftUI app (TradingJournalMini).
 *
 * Usage:
 *   node scripts/desktop-sync-snapshot.mjs export [output.json] [--api=http://localhost:1337/api]
 *   node scripts/desktop-sync-snapshot.mjs import <input.json>  [--api=http://localhost:1337/api]
 */

import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_API = process.env.STRAPI_API_URL || 'http://localhost:1337/api';

function blocksToPlainText(blocks) {
    if (!blocks) return '';
    if (typeof blocks === 'string') return blocks;
    if (!Array.isArray(blocks)) return '';
    return blocks
        .map((block) => {
            if (!Array.isArray(block?.children)) return '';
            return block.children.map((c) => c?.text || '').join('');
        })
        .join('\n');
}

function plainTextToBlocks(text) {
    const str = String(text || '').trim();
    if (!str) return [];
    return str.split('\n').map((line) => ({
        type: 'paragraph',
        children: [{ type: 'text', text: line }],
    }));
}

async function fetchAllPages(apiBase, endpoint, extraParams = {}) {
    let page = 1;
    const pageSize = 100;
    const all = [];

    while (true) {
        const url = new URL(`${apiBase}${endpoint}`);
        url.searchParams.set('pagination[page]', String(page));
        url.searchParams.set('pagination[pageSize]', String(pageSize));
        for (const [k, v] of Object.entries(extraParams)) {
            url.searchParams.set(k, String(v));
        }

        const res = await fetch(url);
        if (!res.ok) {
            throw new Error(`GET ${url.pathname} failed: ${res.status} ${res.statusText}`);
        }
        const json = await res.json();
        const items = Array.isArray(json.data) ? json.data : [];
        all.push(...items);

        const pageCount = json.meta?.pagination?.pageCount || 1;
        if (page >= pageCount || items.length === 0) break;
        page += 1;
    }
    return all;
}

async function exportFromDesktop(apiBase, outputPath) {
    console.log(`[Sync] Fetching data from Desktop Strapi API: ${apiBase} ...`);

    const [rawAccounts, rawSettings, rawStrategies, rawSymbols, rawTrades, rawPlans, rawRoadmaps] = await Promise.all([
        fetchAllPages(apiBase, '/accounts', { 'populate[0]': 'market', 'populate[1]': 'setting', 'populate[2]': 'strategy' }),
        fetchAllPages(apiBase, '/settings', { 'populate[0]': 'account' }),
        fetchAllPages(apiBase, '/strategies'),
        fetchAllPages(apiBase, '/symbols', { 'populate[0]': 'market' }),
        fetchAllPages(apiBase, '/trades', {
            'populate[0]': 'account',
            'populate[1]': 'symbol',
            'populate[2]': 'strategy',
            'populate[3]': 'trade_details',
        }),
        fetchAllPages(apiBase, '/plans'),
        fetchAllPages(apiBase, '/roadmaps', { 'populate[0]': 'account', 'populate[1]': 'setting' }),
    ]);

    const settings = rawSettings.map((s) => ({
        documentId: String(s.documentId || s.id),
        rawId: Number(s.id) || null,
        name: s.Name || s.name || 'Default Risk',
        riskPerTrade: Number(s.riskPerTrade ?? 1.0),
        maxDrawDown: Number(s.maxDrawDown ?? 10.0),
        capitalRisk: Number(s.capitalRisk ?? 15.0),
        accountDocumentId: s.account ? String(s.account.documentId || s.account.id) : null,
        updatedAt: s.updatedAt || new Date().toISOString(),
        isDirty: false,
    }));

    const strategies = rawStrategies.map((st) => ({
        documentId: String(st.documentId || st.id),
        rawId: Number(st.id) || null,
        name: st.name || 'Strategy',
        description: st.description || null,
        type: st.type || 'Rules',
        strategyFile: st.strategyFile || null,
        template: st.template || null,
        updatedAt: st.updatedAt || new Date().toISOString(),
        isDirty: false,
    }));

    const accounts = rawAccounts.map((a) => {
        const settingObj = a.setting
            ? {
                  documentId: String(a.setting.documentId || a.setting.id),
                  rawId: Number(a.setting.id) || null,
                  name: a.setting.Name || a.setting.name || `${a.name} Risk`,
                  riskPerTrade: Number(a.setting.riskPerTrade ?? 1.0),
                  maxDrawDown: Number(a.setting.maxDrawDown ?? 10.0),
                  capitalRisk: Number(a.setting.capitalRisk ?? 15.0),
                  accountDocumentId: String(a.documentId || a.id),
                  updatedAt: a.setting.updatedAt || new Date().toISOString(),
                  isDirty: false,
              }
            : null;

        return {
            documentId: String(a.documentId || a.id),
            rawId: Number(a.id) || null,
            name: a.name || 'Account',
            description: a.description || null,
            initialBalance: Number(a.initial_balance ?? 0),
            cash: a.cash !== null && a.cash !== undefined ? Number(a.cash) : null,
            margin: a.margin !== null && a.margin !== undefined ? Number(a.margin) : null,
            currency: a.currency || 'VND',
            marketDocumentId: a.market ? String(a.market.documentId || a.market.id) : null,
            marketName: a.market ? a.market.Name || a.market.name : null,
            settingDocumentId: settingObj?.documentId || null,
            setting: settingObj,
            strategyDocumentId: a.strategy ? String(a.strategy.documentId || a.strategy.id) : null,
            strategyName: a.strategy ? a.strategy.name : null,
            volumeFormat: a.volumeFormat || null,
            moneyFormat: a.moneyFormat || null,
            feeRate: a.feeRate !== null && a.feeRate !== undefined ? Number(a.feeRate) : null,
            sellTaxRate: a.sellTaxRate !== null && a.sellTaxRate !== undefined ? Number(a.sellTaxRate) : null,
            feePerContract: a.feePerContract !== null && a.feePerContract !== undefined ? Number(a.feePerContract) : null,
            maxPositionPct: a.maxPositionPct !== null && a.maxPositionPct !== undefined ? Number(a.maxPositionPct) : null,
            maxAverageDown: a.maxAverageDown !== null && a.maxAverageDown !== undefined ? Number(a.maxAverageDown) : null,
            timeframe: a.timeframe || null,
            allocationJson: a.allocation ? JSON.stringify(a.allocation) : null,
            updatedAt: a.updatedAt || new Date().toISOString(),
            isDirty: false,
        };
    });

    const symbols = rawSymbols.map((sym) => ({
        documentId: String(sym.documentId || sym.id),
        rawId: Number(sym.id) || null,
        name: String(sym.Name || sym.name || '').toUpperCase(),
        description: sym.Description || sym.description || null,
        exchange: sym.exchange || null,
        shortName: sym.shortName || null,
        industry: sym.industry || null,
        sector: sym.sector || null,
        marketDocumentId: sym.market ? String(sym.market.documentId || sym.market.id) : null,
        lastClose: null,
        prevClose: null,
        lastVolume: null,
        avgVolume20d: null,
        ma20: null,
        lastPriceDate: null,
        updatedAt: sym.updatedAt || new Date().toISOString(),
        isDirty: false,
    }));

    const trades = rawTrades.map((t) => {
        const tradeDocId = String(t.documentId || t.id);
        const details = (t.trade_details || []).map((d) => ({
            documentId: String(d.documentId || d.id),
            rawId: Number(d.id) || null,
            tradeDocumentId: tradeDocId,
            price: Number(d.price ?? 0),
            type: d.type === 'Sell' ? 'Sell' : 'Buy',
            volume: Number(d.volume ?? 0),
            signal: ['Entry', 'TakeProfit', 'Stoploss', 'Exit'].includes(d.signal) ? d.signal : 'Entry',
            date: d.date || t.date || t.createdAt || new Date().toISOString(),
            note: blocksToPlainText(d.note),
            createdAt: d.createdAt || new Date().toISOString(),
            updatedAt: d.updatedAt || new Date().toISOString(),
            isDirty: false,
            isDeleted: false,
        }));

        return {
            documentId: tradeDocId,
            rawId: Number(t.id) || null,
            type: t.type === 'Short' ? 'Short' : 'Long',
            tradeStatus: ['Open', 'Closed', 'ScaleIn', 'ScaleOut'].includes(t.trade_status) ? t.trade_status : 'Open',
            note: blocksToPlainText(t.note),
            date: t.date || t.createdAt || new Date().toISOString(),
            accountDocumentId: t.account ? String(t.account.documentId || t.account.id) : '',
            symbolDocumentId: t.symbol ? String(t.symbol.documentId || t.symbol.id) : null,
            symbolName: String(t.symbol?.Name || t.symbol?.name || 'UNKNOWN').toUpperCase(),
            strategyDocumentId: t.strategy ? String(t.strategy.documentId || t.strategy.id) : null,
            strategyName: t.strategy ? t.strategy.name : null,
            scored: Number(t.scored ?? 0),
            pnl: t.pnl !== null && t.pnl !== undefined ? Number(t.pnl) : null,
            forwardTest: Boolean(t.forward_test),
            backtest: Boolean(t.backtest),
            marketSnapshotJson: t.market_snapshot ? JSON.stringify(t.market_snapshot) : null,
            tradeDetails: details,
            createdAt: t.createdAt || new Date().toISOString(),
            updatedAt: t.updatedAt || new Date().toISOString(),
            isDirty: false,
            isDeleted: false,
        };
    });

    const plans = rawPlans.map((p) => ({
        documentId: String(p.documentId || p.id),
        rawId: Number(p.id) || null,
        accountId: String(p.accountId || ''),
        accountName: String(p.accountName || ''),
        title: String(p.title || 'Plan'),
        scope: p.scope === 'Weekly' ? 'Weekly' : 'Daily',
        planDate: p.planDate || null,
        weekStart: p.weekStart || null,
        weekEnd: p.weekEnd || null,
        session: p.session || null,
        marketContext: p.marketContext || '',
        symbols: p.symbols || '',
        entryPlan: p.entryPlan || '',
        riskPlan: p.riskPlan || '',
        checklist: p.checklist || '',
        reviewNotes: p.reviewNotes || '',
        status: ['Draft', 'Active', 'Done', 'Skipped'].includes(p.status) ? p.status : 'Draft',
        maxTrades: Number(p.maxTrades ?? 3),
        createdAt: p.createdAt || new Date().toISOString(),
        updatedAt: p.updatedAt || new Date().toISOString(),
        isDirty: false,
        isDeleted: false,
    }));

    const roadmaps = rawRoadmaps.map((r) => ({
        documentId: String(r.documentId || r.id),
        rawId: Number(r.id) || null,
        accountDocumentId: r.account ? String(r.account.documentId || r.account.id) : '',
        settingDocumentId: r.setting ? String(r.setting.documentId || r.setting.id) : null,
        startingBalance: Number(r.startingBalance ?? 0),
        targetGrowthPercent: Number(r.targetGrowthPercent ?? 25),
        plannedTrades: Number(r.plannedTrades ?? 25),
        riskPercent: Number(r.riskPercent ?? 1.0),
        rewardMultiple: Number(r.rewardMultiple ?? 2.0),
        maxDrawDownPercent: Number(r.maxDrawDownPercent ?? 10.0),
        status: ['unprocess', 'process', 'completed'].includes(r.status) ? r.status : 'unprocess',
        targetBalance: Number(r.targetBalance ?? 0),
        profitTarget: Number(r.profitTarget ?? 0),
        winRateEstimate: Number(r.winRateEstimate ?? 50),
        snapshotJson: r.snapshot ? JSON.stringify(r.snapshot) : null,
        createdAt: r.createdAt || new Date().toISOString(),
        updatedAt: r.updatedAt || new Date().toISOString(),
        isDirty: false,
        isDeleted: false,
    }));

    const snapshot = {
        schemaVersion: 1,
        exportedAt: new Date().toISOString(),
        sourceDevice: 'Desktop-Strapi-v5',
        accounts,
        settings,
        markets: [],
        strategies,
        symbols,
        trades,
        plans,
        roadmaps,
        allocationSnapshots: [],
        deletedTradeDocumentIds: [],
        deletedTradeDetailDocumentIds: [],
        deletedPlanDocumentIds: [],
        deletedRoadmapDocumentIds: [],
    };

    fs.writeFileSync(outputPath, JSON.stringify(snapshot, null, 2), 'utf8');
    console.log(`[Sync] Exported snapshot to ${outputPath}`);
    console.log(
        `       Accounts: ${accounts.length} | Symbols: ${symbols.length} | Trades: ${trades.length} | Plans: ${plans.length} | Roadmaps: ${roadmaps.length}`
    );
}

async function importToDesktop(apiBase, inputPath) {
    const raw = fs.readFileSync(inputPath, 'utf8');
    const snapshot = JSON.parse(raw);
    console.log(`[Sync] Importing snapshot from ${snapshot.sourceDevice} (${snapshot.exportedAt}) into ${apiBase}...`);

    // 1. Upsert Plans
    for (const plan of snapshot.plans || []) {
        const payload = {
            data: {
                accountId: plan.accountId,
                accountName: plan.accountName,
                title: plan.title,
                scope: plan.scope,
                planDate: plan.planDate,
                weekStart: plan.weekStart,
                weekEnd: plan.weekEnd,
                session: plan.session,
                marketContext: plan.marketContext,
                symbols: plan.symbols,
                entryPlan: plan.entryPlan,
                riskPlan: plan.riskPlan,
                checklist: plan.checklist,
                reviewNotes: plan.reviewNotes,
                status: plan.status,
                maxTrades: plan.maxTrades,
            },
        };

        const checkRes = await fetch(`${apiBase}/plans/${encodeURIComponent(plan.documentId)}`);
        if (checkRes.ok) {
            await fetch(`${apiBase}/plans/${encodeURIComponent(plan.documentId)}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });
        } else {
            await fetch(`${apiBase}/plans`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });
        }
    }

    // 2. Upsert Trades & TradeDetails
    const existingSymbols = await fetchAllPages(apiBase, '/symbols');
    const symbolIdByName = new Map(
        existingSymbols.map((s) => [String(s.Name || s.name || '').toUpperCase(), s.documentId || s.id])
    );

    for (const trade of snapshot.trades || []) {
        const symKey = String(trade.symbolName || '').toUpperCase();
        let symbolId = trade.symbolDocumentId || symbolIdByName.get(symKey);

        if (!symbolId && symKey) {
            const createSymRes = await fetch(`${apiBase}/symbols`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ data: { Name: symKey, Description: symKey } }),
            });
            if (createSymRes.ok) {
                const createdSym = await createSymRes.json();
                symbolId = createdSym.data?.documentId || createdSym.data?.id;
                symbolIdByName.set(symKey, symbolId);
            }
        }

        const tradePayload = {
            data: {
                type: trade.type,
                trade_status: trade.tradeStatus,
                note: plainTextToBlocks(trade.note),
                date: trade.date,
                account: trade.accountDocumentId || undefined,
                symbol: symbolId || undefined,
                strategy: trade.strategyDocumentId || undefined,
                scored: trade.scored,
                pnl: trade.pnl,
                forward_test: trade.forwardTest,
                backtest: trade.backtest,
            },
        };

        let targetTradeDocId = trade.documentId;
        const checkTrade = await fetch(`${apiBase}/trades/${encodeURIComponent(trade.documentId)}`);
        if (checkTrade.ok) {
            await fetch(`${apiBase}/trades/${encodeURIComponent(trade.documentId)}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(tradePayload),
            });
        } else {
            const createRes = await fetch(`${apiBase}/trades`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(tradePayload),
            });
            if (createRes.ok) {
                const created = await createRes.json();
                targetTradeDocId = created.data?.documentId || created.data?.id;
            }
        }

        for (const d of trade.tradeDetails || []) {
            const detailPayload = {
                data: {
                    price: d.price,
                    type: d.type,
                    volume: d.volume,
                    signal: d.signal,
                    date: d.date,
                    note: plainTextToBlocks(d.note),
                    trade: targetTradeDocId,
                },
            };
            const checkDetail = await fetch(`${apiBase}/trade-details/${encodeURIComponent(d.documentId)}`);
            if (checkDetail.ok) {
                await fetch(`${apiBase}/trade-details/${encodeURIComponent(d.documentId)}`, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(detailPayload),
                });
            } else {
                await fetch(`${apiBase}/trade-details`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(detailPayload),
                });
            }
        }
    }

    console.log('[Sync] Import into Desktop Strapi completed successfully!');
}

async function main() {
    const args = process.argv.slice(2);
    const command = args[0];
    const fileArg = args.find((a, idx) => idx > 0 && !a.startsWith('--'));
    const apiFlag = args.find((a) => a.startsWith('--api='));
    const apiBase = apiFlag ? apiFlag.slice('--api='.length).replace(/\/$/, '') : DEFAULT_API;

    if (command === 'export') {
        const out = path.resolve(fileArg || 'tradingjournal_sync_desktop.json');
        await exportFromDesktop(apiBase, out);
    } else if (command === 'import') {
        if (!fileArg) {
            console.error('Error: Missing input JSON file. Usage: node scripts/desktop-sync-snapshot.mjs import <file.json>');
            process.exit(1);
        }
        await importToDesktop(apiBase, path.resolve(fileArg));
    } else {
        console.log('Usage:');
        console.log('  node scripts/desktop-sync-snapshot.mjs export [output.json] [--api=http://localhost:1337/api]');
        console.log('  node scripts/desktop-sync-snapshot.mjs import <input.json>  [--api=http://localhost:1337/api]');
    }
}

main().catch((err) => {
    console.error('[Sync Error]', err.message || err);
    process.exit(1);
});

