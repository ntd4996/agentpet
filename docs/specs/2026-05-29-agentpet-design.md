# AgentPet, Design Spec

Ngày: 2026-05-29
Trạng thái: Approved (brainstorm)

## 1. Tóm tắt

AgentPet là app menu bar macOS native (Swift/SwiftUI): một con pet sống trên desktop phản ứng theo trạng thái các AI coding agent đang chạy (Claude Code, Codex, ...). App cho biết agent nào đang chạy, con nào đã xong, con nào đang chờ người dùng nhập input. Mục tiêu: vừa vui và dễ lan truyền (như Petdex), vừa là tiện ích thật cho dev chạy nhiều agent song song. Dự án open-source, định hướng kéo sao GitHub.

Quyết định nền tảng (chốt trong brainstorm):
- Bản phát hành desktop hiện tại là macOS native (Swift/SwiftUI).
- Không port SwiftUI/AppKit sang Windows; Apple UI framework không có trên Windows.
- Giữ logic thuần Swift trong `AgentPetCore` để build/test được trên Windows khi toolchain hỗ trợ.
- Prototype Windows dùng UI native riêng bằng C# WPF trong `Windows/`, dùng cùng event/state model thay vì chia sẻ UI macOS.
- SwiftWin32 chỉ là hướng nghiên cứu tương lai, không phải đường UI Windows chính hiện tại.
- Pet phản ứng theo trạng thái agent; cả hai surface: floating pet (tắt được) + menu bar list.
- Phát hiện trạng thái: hook tích hợp là chính, quan sát process thụ động là fallback.
- Pet built-in trước; format pet "mở" sẵn cho v2 (dex cộng đồng + import pet pack).
- MVP dùng 1 pet tổng (aggregate mood); kiến trúc cho phép "pin pet theo project" ở bản sau.

## 2. Kiến trúc

Ba khối tách bạch, giao tiếp qua interface rõ ràng:

1. State daemon (trong app)
   - Giữ state tất cả agent session: `id`, `project` (đường dẫn/cwd), `agentKind` (claude/codex/...), `state`, `updatedAt`, `title/summary` (tuỳ chọn).
   - Lắng nghe trên một Unix domain socket local (vd `~/.agentpet/agentpet.sock`).
   - Nhận event JSON, cập nhật state, publish ra UI (Combine/`@Observable`).
   - Dọn session cũ (timeout / khi nhận event kết thúc).

2. Bridge / CLI helper
   - Binary nhỏ trong cùng repo: `agentpet hook --event <E> --session <id> [--project <path>] [--agent <kind>] [--message <m>]`.
   - Được agent gọi qua cơ chế hook của agent đó; helper serialize event JSON và gửi vào socket.
   - Không phụ thuộc app đang mở: nếu socket không có, ghi tạm vào file queue (`~/.agentpet/queue/`) để daemon đọc khi mở.

3. UI
   - MenuBarExtra: icon menu bar + dropdown list agent.
   - Floating pet window: `NSPanel` borderless, non-activating, level floating, kéo được, tắt được, click-through optional.

Luồng dữ liệu: agent → hook → helper → socket (hoặc file queue) → daemon → publish state → UI observe.

## 3. Phát hiện trạng thái agent

### 3.1 Hook (chính)

Tập trạng thái chuẩn hoá: `registered` / `working` / `waiting` / `done` / `idle`.

Claude Code (cài qua `settings.json` hooks gọi `agentpet hook ...`):
- `SessionStart` → `registered`
- `UserPromptSubmit` / tool đang chạy → `working`
- `Notification` (cần quyền hoặc đợi input) → `waiting`
- `Stop` → `done` (xong lượt), sau timeout ngắn không hoạt động → `idle`

Codex: dùng cơ chế `notify` (chương trình ngoài nhận JSON khi turn hoàn tất) map về cùng tập trạng thái. (Chi tiết Codex thuộc v2.)

Gemini CLI / agent khác: thêm dần qua cùng format helper.

Onboarding: app có nút "Cài hook tự động" để chèn cấu hình hook vào `settings.json` của Claude Code (idempotent, có thể gỡ).

### 3.2 Fallback thụ động

Với agent chưa cài hook: quét process (`claude`, `codex`, ...) để biết `working`/`idle` (chỉ on/off). Không suy ra `waiting`. Đánh dấu nguồn là "passive" để UI thể hiện độ tin cậy thấp hơn.

## 4. Hệ thống pet + format

### 4.1 MVP
- 3-5 pet built-in.
- 1 pet tổng (aggregate). Ưu tiên hiển thị mood:
  1. Có agent `waiting` → pet "ngó/gọi" người dùng (ưu tiên cao nhất).
  2. Mọi agent vừa `done` → pet ăn mừng (celebrate, ngắn rồi về idle).
  3. Có agent `working` → pet làm việc.
  4. Không có gì → idle.

### 4.2 Pet pack format (mở sẵn, bật ở v2)
- Một bundle/folder gồm:
  - `manifest.json`: metadata (name, author, version) + map `state → animation` cho các state: `idle`, `working`, `waiting`, `done`, `celebrate`.
  - assets: sprite frames hoặc Lottie/APNG.
- v2: load pet từ thư mục user (`~/.agentpet/pets/`), cộng đồng PR pet vào repo (dex), importer cho pet pack tương thích.

## 5. UI / tương tác

Menu bar dropdown:
- List agent: dấu chấm màu theo state (waiting=vàng, working=xanh dương, done=xanh lá, idle/passive=xám) + tên project + state + thời gian cập nhật.
- Bấm 1 dòng: focus terminal/cửa sổ tương ứng nếu khả thi (best-effort; nếu không làm được thì bỏ qua trong v1).
- Toggle bật/tắt pet. Mở Settings.

Floating pet:
- Nổi góc màn hình, kéo được, click-through optional, tắt được.
- Bong bóng thoại khi có sự kiện (vd "docs-update xong").

Notification:
- Khi agent chuyển sang `waiting` hoặc `done` → native notification + (tuỳ chọn) âm thanh + animation pet.

## 6. Tech stack
- macOS app: Swift + SwiftUI, `MenuBarExtra` (macOS 13+).
- macOS pet window: `NSPanel` non-activating, level floating.
- Portable Swift core: `AgentPetCore` giữ session state, event model, hook parsing/installing, queue fallback; không import AppKit/SwiftUI/Sparkle.
- Windows prototype: C# WPF shell trong `Windows/src/AgentPet.Windows/`, Windows CLI trong `Windows/src/AgentPet.Cli/`, shared Windows event/state model trong `Windows/src/AgentPet.Core/`.
- Animation: chốt ở giai đoạn plan (ứng viên: SpriteKit hoặc Lottie). MVP có thể dùng sprite sheet đơn giản.
- Helper: Swift CLI nhỏ cho macOS SwiftPM package; Windows prototype có CLI riêng dùng cùng event contract.
- Phát hành macOS: DMG notarized + Homebrew cask. Windows packaging là việc tương lai, chưa phải bản phát hành desktop chính thức.

## 7. Phạm vi

### v1 (MVP)
- Claude Code hook + fallback process scan.
- 3 pet built-in.
- Menu bar list agent.
- Floating pet toggle + aggregate mood.
- Native notification.
- Nút cài hook tự động cho Claude Code.
- Phát hành qua Homebrew cask.

### v2 (sau)
- Codex/Gemini support.
- Pet pack format công khai + dex cộng đồng.
- Pin pet theo project (1 pet/agent).
- Import pet pack.
- Focus cửa sổ terminal theo agent.

## 8. Đòn bẩy kéo sao
- README có GIF demo pet phản ứng.
- Cài 1 lệnh (`brew install ...`).
- Onboarding 1 chạm (nút cài hook tự động).
- CONTRIBUTING hướng dẫn làm pet (v2) để biến user thành contributor.

## 9. Test
- Daemon/state: unit test theo chuỗi event giả lập (socket nhận JSON → state đúng), test timeout/dọn session.
- Helper: test serialize + gửi event đúng format, fallback file queue khi không có socket.
- UI: snapshot/manual cho các pet state.

## 10. Rủi ro / mở
- Quyền macOS cho process scan (fallback) có thể bị hạn chế; cần kiểm chứng.
- Notarization + Homebrew cask cần Apple Developer account.
- Chi tiết cơ chế `notify` của Codex cần xác minh khi làm v2.
- Lựa chọn animation engine (SpriteKit vs Lottie) chốt ở plan.
