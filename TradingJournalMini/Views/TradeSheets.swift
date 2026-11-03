import SwiftUI

// MARK: - Trade Detail & Lifecycle Inspector Sheet (mirrors TradeDetailModal.jsx & TradeLifecycleBox.jsx)

struct TradeDetailInspectorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let trade: Trade
    @State private var showAddExecution = false
    @State private var newSide: OrderSide = .sell
    @State private var newSignal: TradeSignalType = .takeProfit
    @State private var newPriceText: String = ""
    @State private var newVolumeText: String = ""
    @State private var newNoteText: String = ""

    private var liveTrade: Trade {
        store.trades.first(where: { $0.documentId == trade.documentId }) ?? trade
    }

    private var currency: String {
        store.selectedAccount?.currency ?? "VND"
    }

    private var markPrice: Double? {
        store.symbolPricesMap[liveTrade.symbolName.uppercased()]
    }

    private var lifecycle: TradeLifecycleResult {
        TradeCalculator.buildTradeLifecycle(liveTrade, currentPrice: markPrice, account: store.selectedAccount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(liveTrade.symbolName)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundColor(.white)
                            Text(liveTrade.type.rawValue)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((liveTrade.type == .long ? Color.green : Color.red).opacity(0.2))
                                .foregroundColor(liveTrade.type == .long ? .green : .red)
                                .clipShape(Capsule())
                            Text(liveTrade.tradeStatus.labelVN)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                            Spacer()
                        }

                        let totalPnl = lifecycle.summary.total ?? lifecycle.summary.realized
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tổng PnL (Gộp)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(MoneyFormatter.formatSigned(totalPnl, currency: currency))
                                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                    .foregroundColor(totalPnl >= 0 ? .green : .red)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("PnL Ròng (Sau phí & thuế)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                let netTotal = lifecycle.summary.netTotal ?? lifecycle.summary.netRealized
                                Text(MoneyFormatter.formatSigned(netTotal, currency: currency))
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(netTotal >= 0 ? .green : .red)
                            }
                        }

                        Divider().background(Color.white.opacity(0.1))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("KL đang mở")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(MoneyFormatter.formatVolume(lifecycle.summary.openVolume))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("Giá vốn TB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(MoneyFormatter.formatPrice(lifecycle.summary.avgCost))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Phí & Thuế")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(MoneyFormatter.format(lifecycle.summary.costs, currency: currency, compact: true))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Step-by-step Executions (TradeDetails)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Vòng đời Lệnh (Trade Lifecycle)")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Button {
                                newSide = liveTrade.type == .long ? .sell : .buy
                                newSignal = .takeProfit
                                newPriceText = markPrice != nil ? String(markPrice!) : String(lifecycle.summary.avgCost)
                                newVolumeText = String(lifecycle.summary.openVolume)
                                showAddExecution.toggle()
                            } label: {
                                Label("Thêm khớp lệnh", systemImage: "plus.circle.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                        }

                        if showAddExecution {
                            VStack(spacing: 10) {
                                Picker("Chiều", selection: $newSide) {
                                    ForEach(OrderSide.allCases) { s in
                                        Text(s.rawValue).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Picker("Tín hiệu", selection: $newSignal) {
                                    ForEach(TradeSignalType.allCases) { sig in
                                        Text(sig.rawValue).tag(sig)
                                    }
                                }
                                .pickerStyle(.segmented)

                                HStack(spacing: 8) {
                                    TextField("Giá khớp", text: $newPriceText)
                                        .keyboardType(.decimalPad)
                                        .padding(8)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    TextField("Khối lượng", text: $newVolumeText)
                                        .keyboardType(.decimalPad)
                                        .padding(8)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                TextField("Ghi chú lần khớp này...", text: $newNoteText)
                                    .padding(8)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    if let p = Double(newPriceText.replacingOccurrences(of: ",", with: "")),
                                       let v = Double(newVolumeText.replacingOccurrences(of: ",", with: "")),
                                       p > 0, v > 0 {
                                        store.addExecutionDetail(
                                            to: liveTrade,
                                            side: newSide,
                                            signal: newSignal,
                                            price: p,
                                            volume: v,
                                            note: newNoteText
                                        )
                                        showAddExecution = false
                                    }
                                } label: {
                                    Text("Lưu lần khớp lệnh")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        ForEach(lifecycle.steps) { step in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(step.detail.signal.rawValue)
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(step.action == "open" ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2))
                                        .foregroundColor(step.action == "open" ? .blue : .purple)
                                        .clipShape(Capsule())

                                    Text("\(step.detail.type.rawValue) \(MoneyFormatter.formatVolume(step.volume)) @ \(MoneyFormatter.formatPrice(step.price))")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)

                                    if let addType = step.addType, addType != "initial" {
                                        Text(addType == "pyramid" ? "Pyramid" : "Avg Down")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background((addType == "pyramid" ? Color.green : Color.orange).opacity(0.2))
                                            .foregroundColor(addType == "pyramid" ? .green : .orange)
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    if step.action == "close" {
                                        Text(MoneyFormatter.formatSigned(step.realized, currency: currency, compact: true))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(step.realized >= 0 ? .green : .red)
                                    }
                                }

                                HStack {
                                    Text(step.detail.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("Tồn: \(MoneyFormatter.formatVolume(step.position)) · Giá TB: \(MoneyFormatter.formatPrice(step.avgCost))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if !step.detail.note.isEmpty {
                                    Text(step.detail.note)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.75))
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.10, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Delete button
                    Button(role: .destructive) {
                        store.deleteTrade(liveTrade)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Xóa lệnh giao dịch này")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(14)
            }
            .background(Color(red: 0.06, green: 0.08, blue: 0.12))
            .navigationTitle("Chi tiết Lệnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - New Trade Editor Sheet

struct TradeEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let tradeToEdit: Trade?

    @State private var symbolName: String = ""
    @State private var direction: TradeDirection = .long
    @State private var status: TradeStatus = .open
    @State private var entryPriceText: String = ""
    @State private var entryVolumeText: String = ""
    @State private var score: Int = 8
    @State private var noteText: String = ""
    @State private var tradeDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin Lệnh") {
                    TextField("Mã CK / Phái sinh / Crypto (VD: FPT, VN30F1M)", text: $symbolName)
                        .textInputAutocapitalization(.characters)
                    Picker("Chiều giao dịch", selection: $direction) {
                        ForEach(TradeDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                    Picker("Trạng thái", selection: $status) {
                        ForEach(TradeStatus.allCases) { st in
                            Text(st.labelVN).tag(st)
                        }
                    }
                    DatePicker("Thời gian mở", selection: $tradeDate)
                }

                Section("Khớp lệnh Mở vị thế (Entry)") {
                    TextField("Giá khớp Entry", text: $entryPriceText)
                        .keyboardType(.decimalPad)
                    TextField("Khối lượng", text: $entryVolumeText)
                        .keyboardType(.decimalPad)
                }

                Section("Đánh giá & Nhật ký") {
                    Stepper("Điểm kỷ luật (Score): \(score)/10", value: $score, in: 1...10)
                    TextField("Lý do vào lệnh, cảm xúc, bối cảnh thị trường...", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(tradeToEdit == nil ? "Thêm Lệnh Mới" : "Sửa Lệnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveNewTrade()
                        dismiss()
                    }
                    .disabled(symbolName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveNewTrade() {
        guard let acc = store.selectedAccount else { return }
        let sym = symbolName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let price = Double(entryPriceText.replacingOccurrences(of: ",", with: "")) ?? 0
        let vol = Double(entryVolumeText.replacingOccurrences(of: ",", with: "")) ?? 0
        let tradeId = "trd_\(UUID().uuidString.lowercased().prefix(12))"

        var details: [TradeDetail] = []
        if price > 0 && vol > 0 {
            details.append(TradeDetail(
                documentId: "td_\(UUID().uuidString.lowercased().prefix(12))",
                rawId: nil,
                tradeDocumentId: tradeId,
                price: price,
                type: direction == .long ? .buy : .sell,
                volume: vol,
                signal: .entry,
                date: tradeDate,
                note: "Entry mở vị thế",
                createdAt: Date(),
                updatedAt: Date(),
                isDirty: true,
                isDeleted: false
            ))
        }

        let newTrade = Trade(
            documentId: tradeId,
            rawId: nil,
            type: direction,
            tradeStatus: status,
            note: noteText,
            date: tradeDate,
            accountDocumentId: acc.documentId,
            symbolDocumentId: nil,
            symbolName: sym,
            strategyDocumentId: acc.strategyDocumentId,
            strategyName: acc.strategyName,
            scored: score,
            pnl: nil,
            forwardTest: false,
            backtest: false,
            marketSnapshotJson: nil,
            tradeDetails: details,
            createdAt: Date(),
            updatedAt: Date(),
            isDirty: true,
            isDeleted: false
        )
        store.saveTrade(newTrade)
    }
}

// MARK: - Plan Form Sheet

struct PlanFormSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var scope: PlanScope = .daily
    @State private var status: PlanStatus = .active
    @State private var symbols: String = ""
    @State private var marketContext: String = ""
    @State private var entryPlan: String = ""
    @State private var riskPlan: String = ""
    @State private var maxTrades: Int = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin Kế hoạch") {
                    TextField("Tiêu đề kế hoạch", text: $title)
                    Picker("Phạm vi", selection: $scope) {
                        ForEach(PlanScope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    Picker("Trạng thái", selection: $status) {
                        ForEach(PlanStatus.allCases) { st in
                            Text(st.rawValue).tag(st)
                        }
                    }
                    Stepper("Số lệnh tối đa: \(maxTrades)", value: $maxTrades, in: 1...15)
                }

                Section("Danh mục & Kịch bản") {
                    TextField("Danh sách mã theo dõi (VD: FPT, SSI, MWG)", text: $symbols)
                        .textInputAutocapitalization(.characters)
                    TextField("Nhận định thị trường chung", text: $marketContext, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Kịch bản điểm mua (Entry Plan)", text: $entryPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Quản trị rủi ro (Risk Plan)", text: $riskPlan, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Tạo Kế Hoạch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveNewPlan()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveNewPlan() {
        guard let acc = store.selectedAccount else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let todayStr = df.string(from: Date())

        let plan = TradingPlan(
            documentId: "plan_\(UUID().uuidString.lowercased().prefix(12))",
            rawId: nil,
            accountId: acc.documentId,
            accountName: acc.name,
            title: title,
            scope: scope,
            planDate: todayStr,
            weekStart: todayStr,
            weekEnd: nil,
            session: "Cả ngày",
            marketContext: marketContext,
            symbols: symbols,
            entryPlan: entryPlan,
            riskPlan: riskPlan,
            checklist: "",
            reviewNotes: "",
            status: status,
            maxTrades: maxTrades,
            createdAt: Date(),
            updatedAt: Date(),
            isDirty: true,
            isDeleted: false
        )
        store.savePlan(plan)
    }
}

