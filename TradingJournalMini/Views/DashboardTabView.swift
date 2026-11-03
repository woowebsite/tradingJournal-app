import SwiftUI
import Charts

enum DashboardSegment: String, CaseIterable, Identifiable {
    case overview = "Tổng quan"
    case monitor = "Sức khỏe & Risk"
    case allocation = "Phân bổ vốn"
    var id: String { rawValue }
}

struct DashboardTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var segment: DashboardSegment = .overview

    private var currentAccount: Account? {
        store.selectedAccount
    }

    private var metrics: AccountPerformanceMetrics? {
        guard let acc = currentAccount else { return nil }
        return RiskAnalyticsEngine.analyzeAccount(
            account: acc,
            trades: store.accountTrades,
            symbolPrices: store.symbolPricesMap
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Chế độ xem", selection: $segment) {
                        ForEach(DashboardSegment.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    if let acc = currentAccount, let m = metrics {
                        switch segment {
                        case .overview:
                            OverviewSectionView(account: acc, metrics: m)
                        case .monitor:
                            MonitorHealthSectionView(account: acc, metrics: m)
                        case .allocation:
                            AssetAllocationSectionView()
                        }
                    } else {
                        ContentUnavailableView("Chưa có tài khoản", systemImage: "wallet.pass")
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.06, green: 0.08, blue: 0.12))
            .navigationBarHidden(true)
        }
    }
}

// MARK: - 1. Overview Section

struct OverviewSectionView: View {
    let account: Account
    let metrics: AccountPerformanceMetrics

    var body: some View {
        VStack(spacing: 14) {
            // Hero Equity Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TÀI SẢN RÒNG (EQUITY)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%@%.2f%%", metrics.returnPct >= 0 ? "+" : "", metrics.returnPct))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((metrics.returnPct >= 0 ? Color.green : Color.red).opacity(0.18))
                        .foregroundColor(metrics.returnPct >= 0 ? .green : .red)
                        .clipShape(Capsule())
                }

                Text(MoneyFormatter.format(metrics.currentEquity, currency: account.currency))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vốn ban đầu")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(MoneyFormatter.format(metrics.initialBalance, currency: account.currency, compact: true))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PnL Đã chốt")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(MoneyFormatter.formatSigned(metrics.realizedPnl, currency: account.currency, compact: true))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(metrics.realizedPnl >= 0 ? .green : .red)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PnL Vị thế mở")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(MoneyFormatter.formatSigned(metrics.unrealizedPnl, currency: account.currency, compact: true))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(metrics.unrealizedPnl >= 0 ? .green : .red)
                    }
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.16, blue: 0.26), Color(red: 0.09, green: 0.11, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 14)

            // 4 KPI Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricStatCard(
                    title: "Win Rate",
                    value: String(format: "%.1f%%", metrics.winRate),
                    subtitle: "\(metrics.winCount) Thắng · \(metrics.lossCount) Thua",
                    accent: metrics.winRate >= 50 ? .green : .orange
                )
                MetricStatCard(
                    title: "Profit Factor",
                    value: metrics.profitFactor != nil ? String(format: "%.2f", metrics.profitFactor!) : "--",
                    subtitle: "Kỳ vọng: \(MoneyFormatter.format(metrics.expectancy, currency: account.currency, compact: true))/lệnh",
                    accent: (metrics.profitFactor ?? 0) >= 1.5 ? .green : .blue
                )
                MetricStatCard(
                    title: "TB Lệnh Thắng / Thua",
                    value: MoneyFormatter.format(metrics.avgWin, currency: account.currency, compact: true),
                    subtitle: "TB Thua: -\(MoneyFormatter.format(metrics.avgLoss, currency: account.currency, compact: true))",
                    accent: .cyan
                )
                MetricStatCard(
                    title: "Vị thế đang mở",
                    value: "\(metrics.openTradeCount) lệnh",
                    subtitle: String(format: "Tỷ trọng: %.1f%% NAV", metrics.openExposurePct),
                    accent: .purple
                )
            }
            .padding(.horizontal, 14)

            // Equity Curve Chart
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Đường cong vốn (Equity Curve)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Max DD: -\(String(format: "%.1f%%", metrics.maxDrawdownPct))")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if metrics.equityCurve.count >= 2 {
                    Chart(metrics.equityCurve) { point in
                        LineMark(
                            x: .value("Ngày", point.day),
                            y: .value("Equity", point.equity)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.blue)

                        AreaMark(
                            x: .value("Ngày", point.day),
                            y: .value("Equity", point.equity)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                } else {
                    Text("Chưa đủ điểm dữ liệu lịch sử để vẽ biểu đồ.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - 2. Monitor & Account Health Section (mirrors Monitor.jsx & AccountHealthCard.jsx)

struct MonitorHealthSectionView: View {
    let account: Account
    let metrics: AccountPerformanceMetrics

    private var verdictColor: Color {
        switch metrics.verdictLevel {
        case "action": return .red
        case "watch": return .orange
        case "ok": return .green
        default: return .blue
        }
    }

    private var verdictTitle: String {
        switch metrics.verdictLevel {
        case "action": return "CẦN HÀNH ĐỘNG NGAY"
        case "watch": return "CẦN THEO DÕI"
        case "ok": return "HỆ THỐNG ỔN ĐỊNH"
        default: return "ĐANG THU THẬP DỮ LIỆU"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Verdict Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: metrics.verdictLevel == "action" ? "exclamationmark.triangle.fill" : "shield.lefthalf.filled.badge.checkmark")
                        .foregroundColor(verdictColor)
                    Text(verdictTitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(verdictColor)
                    Spacer()
                    Text("TF: \(account.timeframe ?? "Chưa đặt")")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                ForEach(metrics.verdictReasons, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(verdictColor)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(reason)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding(14)
            .background(verdictColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(verdictColor.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            // Drawdown Budget Gauge
            let ddLimit = account.setting?.maxDrawDown ?? 10.0
            let ddRatio = ddLimit > 0 ? min(1.0, metrics.currentDrawdownPct / ddLimit) : 0.0

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hạn mức Sụt giảm Vốn (Drawdown Limit)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1f%% / %.1f%%", metrics.currentDrawdownPct, ddLimit))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(ddRatio >= 0.8 ? .red : .green)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 10)
                        Capsule()
                            .fill(ddRatio >= 1.0 ? Color.red : (ddRatio >= 0.8 ? Color.orange : Color.green))
                            .frame(width: max(6, geo.size.width * ddRatio), height: 10)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("Rủi ro/lệnh: \(String(format: "%.2f%%", account.setting?.riskPerTrade ?? 1.0))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Chuỗi thua dài nhất: \(metrics.maxLosingStreak) lệnh")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - 3. Cross-Account Asset Allocation Section (mirrors AssetAllocation.jsx)

struct AssetAllocationSectionView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("tj_usd_vnd_rate") private var usdVndRate: Double = 25_400

    private var accountSummaries: [(account: Account, equityVND: Double, pnlVND: Double)] {
        store.accounts.map { acc in
            let accTrades = store.trades.filter { $0.accountDocumentId == acc.documentId && !$0.isDeleted }
            let m = RiskAnalyticsEngine.analyzeAccount(account: acc, trades: accTrades, symbolPrices: store.symbolPricesMap)
            let rate = acc.currency.uppercased() == "USD" ? usdVndRate : 1.0
            return (acc, m.currentEquity * rate, m.totalPnl * rate)
        }
    }

    private var totalPortfolioVND: Double {
        accountSummaries.reduce(0.0) { $0 + $1.equityVND }
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TỔNG TÀI SẢN ĐA TÀI KHOẢN (QUY ĐỔI VND)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text(MoneyFormatter.format(totalPortfolioVND, currency: "VND"))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Tỷ giá quy đổi USD/VND: \(MoneyFormatter.formatPrice(usdVndRate)) ₫")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(red: 0.10, green: 0.13, blue: 0.19))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            ForEach(accountSummaries, id: \.account.documentId) { item in
                let weight = totalPortfolioVND > 0 ? (item.equityVND / totalPortfolioVND) * 100.0 : 0.0
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.account.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(item.account.marketName ?? "Market") · \(item.account.strategyName ?? "Strategy")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f%%", weight))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                            Text(MoneyFormatter.format(item.equityVND, currency: "VND", compact: true))
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }

                    ProgressView(value: min(max(weight, 0), 100), total: 100)
                        .tint(.blue)
                }
                .padding(14)
                .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)
            }
        }
    }
}

struct MetricStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(accent)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(red: 0.10, green: 0.13, blue: 0.19))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

