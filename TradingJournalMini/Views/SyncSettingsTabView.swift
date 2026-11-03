import SwiftUI
import UniformTypeIdentifiers

struct SyncSettingsTabView: View {
    @EnvironmentObject var store: AppStore

    @State private var importMode: SyncImportMode = .merge
    @State private var isExportingFile = false
    @State private var isImportingFile = false
    @State private var exportDocument: SnapshotJSONDocument?
    @State private var statusBanner: (isError: Bool, message: String)?

    // Risk Setting form states
    @State private var riskPerTradeText: String = "1.0"
    @State private var maxDrawdownText: String = "10.0"
    @State private var capitalRiskText: String = "15.0"
    @State private var timeframeText: String = "D1"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Sync Snapshot Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ĐỒNG BỘ VỚI DESKTOP (JSON SNAPSHOT)")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(.white)
                                Text("Chia sẻ qua iCloud Drive, AirDrop hoặc ứng dụng Tệp (Files)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        Divider().background(Color.white.opacity(0.1))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thay đổi trên iPhone chờ Sync")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(store.dirtyChangesCount) bản ghi")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(store.dirtyChangesCount > 0 ? .orange : .green)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Tổng dữ liệu Local SQLite")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(store.accounts.count) TK · \(store.trades.count) Lệnh · \(store.plans.count) Plan")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Chế độ khi Nhập (Import) từ Desktop:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Chế độ Import", selection: $importMode) {
                                ForEach(SyncImportMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.blue)
                        }

                        HStack(spacing: 10) {
                            Button {
                                prepareAndExportSnapshot()
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Xuất JSON Snapshot")
                                        .fontWeight(.bold)
                                }
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                isImportingFile = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Nhập JSON Snapshot")
                                        .fontWeight(.bold)
                                }
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        if let banner = statusBanner {
                            Text(banner.message)
                                .font(.caption)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((banner.isError ? Color.red : Color.green).opacity(0.16))
                                .foregroundColor(banner.isError ? .red : .green)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 14)

                    // 2. Active Account Risk Settings (mirrors Settings.jsx)
                    if let acc = store.selectedAccount {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CÀI ĐẶT QUẢN TRỊ RỦI RO (\(acc.name.uppercased()))")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rủi ro / Lệnh (%)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("1.0", text: $riskPerTradeText)
                                        .keyboardType(.decimalPad)
                                        .padding(10)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Max Drawdown (%)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("10.0", text: $maxDrawdownText)
                                        .keyboardType(.decimalPad)
                                        .padding(10)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tổng vốn rủi ro (%)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("15.0", text: $capitalRiskText)
                                        .keyboardType(.decimalPad)
                                        .padding(10)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Khung thời gian (TF)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("D1, H4, M15...", text: $timeframeText)
                                        .textInputAutocapitalization(.characters)
                                        .padding(10)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }

                            Button {
                                store.updateAccountRiskSetting(
                                    account: acc,
                                    riskPerTrade: Double(riskPerTradeText) ?? 1.0,
                                    maxDrawDown: Double(maxDrawdownText) ?? 10.0,
                                    capitalRisk: Double(capitalRiskText) ?? 15.0,
                                    timeframe: timeframeText
                                )
                                statusBanner = (false, "Đã lưu cấu hình rủi ro cho tài khoản \(acc.name).")
                            } label: {
                                Text("Lưu Cài Đặt Rủi Ro")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 14)
                        .onAppear {
                            loadAccountRiskFields(acc)
                        }
                        .onChange(of: store.selectedAccountId) { _, _ in
                            if let updated = store.selectedAccount {
                                loadAccountRiskFields(updated)
                            }
                        }
                    }

                    // 3. Database Maintenance
                    VStack(alignment: .leading, spacing: 10) {
                        Text("QUẢN LÝ CƠ SỞ DỮ LIỆU LOCAL")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.secondary)

                        Button {
                            SQLiteDatabase.shared.clearAllData()
                            store.seedDemoData()
                            store.reloadFromDatabase()
                            statusBanner = (false, "Đã khôi phục bộ dữ liệu mẫu (VNStock, Phái sinh VN30F1M & Crypto).")
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Khôi phục Dữ liệu Mẫu (Demo Seed)")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .foregroundColor(.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 14)
                }
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Color(red: 0.06, green: 0.08, blue: 0.12))
            .navigationBarHidden(true)
            .fileExporter(
                isPresented: $isExportingFile,
                document: exportDocument,
                contentType: .json,
                defaultFilename: SyncSnapshotManager.shared.defaultExportFilename()
            ) { result in
                switch result {
                case .success(let url):
                    store.markLocalChangesSynced()
                    statusBanner = (false, "Đã xuất Snapshot thành công: \(url.lastPathComponent)")
                case .failure(let error):
                    statusBanner = (true, "Lỗi xuất file: \(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
        }
    }

    private func loadAccountRiskFields(_ acc: Account) {
        riskPerTradeText = String(format: "%.1f", acc.setting?.riskPerTrade ?? 1.0)
        maxDrawdownText = String(format: "%.1f", acc.setting?.maxDrawDown ?? 10.0)
        capitalRiskText = String(format: "%.1f", acc.setting?.capitalRisk ?? 15.0)
        timeframeText = acc.timeframe ?? "D1"
    }

    private func prepareAndExportSnapshot() {
        do {
            let data = try store.exportSyncSnapshotData()
            exportDocument = SnapshotJSONDocument(data: data)
            isExportingFile = true
        } catch {
            statusBanner = (true, "Không thể tạo JSON Snapshot: \(error.localizedDescription)")
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try store.importSyncSnapshotData(data, mode: importMode)
                statusBanner = (
                    false,
                    "Đồng bộ thành công từ \(summary.sourceDevice): \(summary.accountsCount) TK, \(summary.tradesCount) Lệnh (\(summary.tradeDetailsCount) khớp lệnh), \(summary.plansCount) Plan, \(summary.roadmapsCount) Roadmap."
                )
            } catch {
                statusBanner = (true, "Lỗi đọc file Snapshot: \(error.localizedDescription)")
            }
        case .failure(let error):
            statusBanner = (true, "Đã hủy hoặc lỗi chọn file: \(error.localizedDescription)")
        }
    }
}

