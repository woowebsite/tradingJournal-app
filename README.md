# TradingJournal Mini (iOS / SwiftUI Native)

Phiên bản **iPhone / iOS (SwiftUI Native)** rút gọn từ ứng dụng Desktop `tradingJournal`, được thiết kế tối ưu cho thao tác một tay trên iPhone, sử dụng **SQLite3 nội bộ** (`libsqlite3`) và đồng bộ 2 chiều với bản Desktop thông qua **JSON Sync Snapshot** (qua iCloud Drive, AirDrop, Files, Zalo/Telegram).

Toàn bộ các chức năng thuộc menu **Management** trên Desktop (Manage Market, Scored, Manage Strategies/Rules/Backtest, Manage Webhooks, Manage Watchlists, Manage Symbols, Manage Accounts) đã được lược bỏ để ứng dụng nhẹ, tập trung vào theo dõi và ghi nhật ký hằng ngày.

---

## 1. Cấu trúc Dự án

```text
tradingJournal-app/
├── TradingJournalMini.xcodeproj/         # Xcode 16 Project (mở trực tiếp trên macOS)
├── TradingJournalMini/
│   ├── TradingJournalMiniApp.swift       # Entry point + tự động nhận file .json qua onOpenURL
│   ├── Database/
│   │   ├── DatabaseSchema.sql            # Thiết kế bảng SQLite ánh xạ 1-1 với Strapi v5 Desktop
│   │   ├── SQLiteDatabase.swift          # Engine SQLite3 thuần (Zero third-party dependency)
│   │   └── SyncSnapshotManager.swift     # Xuất / Nhập JSON Sync Snapshot (Smart 2-Way Merge & Replace)
│   ├── Models/
│   │   └── DomainModels.swift            # Models + bộ chuyển đổi Strapi v5 RichText Blocks <-> String
│   ├── Utilities/
│   │   └── TradeCalculations.swift       # Port 100% công thức từ Desktop (PnL, Phái sinh 100k/điểm, Lifecycle, Roadmap, Risk)
│   ├── ViewModels/
│   │   └── AppStore.swift                # State management + Demo Seed Data (VNStock, VN30F1M, Crypto)
│   └── Views/
│       ├── MainTabView.swift             # Thanh chọn Active Account cố định + 4 Tab chính
│       ├── DashboardTabView.swift        # Tổng quan Equity, Biểu đồ vốn, Sức khỏe TK & Phân bổ vốn
│       ├── TradeStationMiniTabView.swift # Today Trades, Today Portfolio & Công cụ Tính KL / R:R
│       ├── JournalTabView.swift          # Danh sách Lệnh, Lịch PnL (Calendar), Kế hoạch (Plan) & Roadmap
│       ├── TradeSheets.swift             # Chi tiết vòng đời lệnh (Trade Lifecycle), Thêm khớp lệnh, Tạo Plan
│       └── SyncSettingsTabView.swift     # Xuất / Nhập JSON Sync Snapshot & Cài đặt Rủi ro
├── scripts/
│   └── desktop-sync-snapshot.mjs         # Công cụ CLI xuất/nhập JSON Snapshot trực tiếp từ Strapi Desktop
└── sample_desktop_sync_snapshot.json     # File Snapshot mẫu để test tính năng Import trên iPhone
```

---

## 2. Thiết kế Database & Cơ chế Đồng bộ (Sync) với Desktop

1. **Khóa chính đồng nhất (`document_id` + `raw_id`)**:
   - Mọi bảng trong SQLite (`accounts`, `settings`, `symbols`, `strategies`, `trades`, `trade_details`, `plans`, `roadmaps`) đều dùng `document_id` (chuỗi định danh chuẩn của Strapi v5 trên Desktop) làm khóa chính, kèm `raw_id` (ID số nguyên trong PostgreSQL).
2. **Theo dõi thay đổi Offline (`updated_at`, `is_dirty`, `is_deleted`)**:
   - Khi bạn thêm/sửa/đóng lệnh hoặc tạo Plan trên iPhone, bản ghi được đánh dấu `is_dirty = 1` và cập nhật `updated_at`.
   - Khi **Import JSON Snapshot** ở chế độ **Gộp thông minh (2 chiều)**, ứng dụng so sánh `updatedAt` theo nguyên tắc *Last-Write-Wins*, giữ nguyên các thay đổi mới hơn trên iPhone mà không bị ghi đè mất.
3. **Tự động chuyển đổi định dạng `note` (Strapi Blocks <-> Plain Text)**:
   - Trên Desktop, trường `note` của `trades` và `trade_details` lưu dạng mảng JSON `blocks` của Strapi v5. Công cụ đồng bộ tự động chuyển đổi 2 chiều giữa `blocks` và văn bản thuần trên iPhone.

---

## 3. Hướng dẫn Đồng bộ giữa Desktop và iPhone

### Bước 1: Xuất dữ liệu từ Desktop ra file JSON Snapshot
Khi backend Desktop (`D:\PROGRAMMING\MyGithub\tradingJournal\backend`) đang chạy ở cổng `1337`:
```bash
node scripts/desktop-sync-snapshot.mjs export ./tradingjournal_sync_desktop.json
```
*(Gửi file `tradingjournal_sync_desktop.json` sang iPhone qua iCloud Drive, AirDrop hoặc Zalo/Telegram).*

### Bước 2: Nhập vào iPhone
- Mở ứng dụng **TradeJournal Mini** trên iPhone -> vào tab **Sync & Cài đặt** -> nhấn **Nhập JSON Snapshot** (hoặc chạm trực tiếp vào file `.json` trong ứng dụng **Tệp / Files** trên iPhone và chọn mở bằng **TradeJournal Mini**).

### Bước 3: Đồng bộ ngược từ iPhone về lại Desktop
- Trên iPhone: vào tab **Sync & Cài đặt** -> nhấn **Xuất JSON Snapshot** -> lưu file vào iCloud Drive hoặc gửi về máy tính.
- Trên máy tính: chạy lệnh sau để đẩy toàn bộ lệnh mới, lần khớp lệnh (`trade_details`) và `plan` từ iPhone vào PostgreSQL của Desktop:
```bash
node scripts/desktop-sync-snapshot.mjs import ./tradingjournal_sync_from_iphone.json
```

