import SwiftUI

@main
struct TradingJournalMiniApp: App {
    @StateObject private var store = AppStore()
    @State private var incomingImportMessage: String?

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .onOpenURL { url in
                    handleIncomingSnapshotURL(url)
                }
                .alert("Đồng bộ Snapshot", isPresented: Binding(
                    get: { incomingImportMessage != nil },
                    set: { if !$0 { incomingImportMessage = nil } }
                )) {
                    Button("Đóng", role: .cancel) { incomingImportMessage = nil }
                } message: {
                    Text(incomingImportMessage ?? "")
                }
        }
    }

    private func handleIncomingSnapshotURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "json" else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let summary = try store.importSyncSnapshotData(data, mode: .merge)
            incomingImportMessage = "Đã gộp thành công từ \(summary.sourceDevice): \(summary.accountsCount) TK, \(summary.tradesCount) Lệnh, \(summary.plansCount) Kế hoạch."
        } catch {
            incomingImportMessage = "Không thể nhập file JSON: \(error.localizedDescription)"
        }
    }
}

