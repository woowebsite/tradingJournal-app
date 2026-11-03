import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Int = 0
    @State private var showNewTradeSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Persistent iPhone Top Header with Active Account Selector (mirrors Sidebar.jsx Active Account)
            TopAccountHeaderBar(showNewTradeSheet: $showNewTradeSheet)

            TabView(selection: $selectedTab) {
                DashboardTabView()
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(0)

                TradeStationMiniTabView()
                    .tabItem {
                        Label("Today", systemImage: "bolt.shield.fill")
                    }
                    .tag(1)

                JournalTabView()
                    .tabItem {
                        Label("Journal", systemImage: "book.pages.fill")
                    }
                    .tag(2)

                SyncSettingsTabView()
                    .tabItem {
                        Label("Sync & Cài đặt", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .badge(store.dirtyChangesCount > 0 ? store.dirtyChangesCount : 0)
                    .tag(3)
            }
            .tint(.blue)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showNewTradeSheet) {
            TradeEditorSheet(tradeToEdit: nil)
                .environmentObject(store)
        }
    }
}

struct TopAccountHeaderBar: View {
    @EnvironmentObject var store: AppStore
    @Binding var showNewTradeSheet: Bool

    var body: some View {
        HStack(spacing: 10) {
            // App Logo Badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                Text("TJ")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }

            // Account Picker Menu
            Menu {
                ForEach(store.accounts) { acc in
                    Button {
                        store.selectedAccountId = acc.documentId
                    } label: {
                        HStack {
                            Text("\(acc.name) (\(acc.currency))")
                            if acc.documentId == store.selectedAccount?.documentId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(store.selectedAccount?.name ?? "Chọn tài khoản")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        if let acc = store.selectedAccount {
                            Text("\(acc.marketName ?? "Market") · TF \(acc.timeframe ?? "D1") · Vốn \(MoneyFormatter.format(acc.initialBalance, currency: acc.currency, compact: true))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            if store.dirtyChangesCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("\(store.dirtyChangesCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            }

            Button {
                showNewTradeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Lệnh")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.09, green: 0.11, blue: 0.16))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

