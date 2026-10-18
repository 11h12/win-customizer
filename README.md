# Windows Customizer

PowerShell toolkit hỗ trợ quy trình dựng Windows image: dọn dẹp và xuất cấu hình, tạo `unattend.xml` theo lựa chọn locale/OOBE, chạy Sysprep trong Audit Mode, capture bằng DISM và hoàn thiện WIM/ESD/ISO. Mỗi tác vụ có trạng thái riêng; bước DISM/copy dài hiển thị tiến trình.

## Quy trình

1. Cài Windows và hoàn thành toàn bộ OOBE bằng một tài khoản tạm. Cài driver, ứng dụng, cập nhật và khởi động lại đến khi Windows Update hoàn tất.
2. Từ Windows đã setup, mở Sysprep GUI và chọn **Enter System Audit Mode** rồi reboot. Không dùng `Ctrl+Shift+F3` tại OOBE đầu tiên cho quy trình này.
3. Trước khi vào Audit, export Default apps/Start layout trong user tạm. Trong Audit Mode, xóa profile và tài khoản tạm, cấu hình Desktop/portable app shortcuts, rồi chạy cleanup. Toolkit mở thư mục Start Menu chung: `C:\ProgramData\Microsoft\Windows\Start Menu\Programs`.
4. Tạo `unattend.xml`, khai báo locale/ngôn ngữ/keyboard/timezone, tùy chọn tạo local account và chọn các trang OOBE. Xác minh bằng Windows SIM đúng phiên bản Windows.
5. Chạy final Sysprep bằng built-in Administrator (SID kết thúc `-500`); máy sẽ tắt. Boot WinPE và capture phân vùng Windows ra ổ BACKUP.
6. Trên Windows host, map `BACKUP.vmdk`, copy image vào thư mục build, xem/sửa metadata, append index nếu có nhiều image, mount/import/verify app associations, commit, tùy chọn xuất ESD, thay image trong ISO và verify ISO.

Hướng dẫn đầy đủ và thứ tự từng tác vụ ở [`docs/BUILD_GUIDE_VI.md`](docs/BUILD_GUIDE_VI.md). Đối chiếu từng bước với bài nguồn và các tài liệu Microsoft ở [`docs/SOURCE_AUDIT_VI.md`](docs/SOURCE_AUDIT_VI.md).

## Thành phần

- [`scripts/WinCustomizer_Toolkit.ps1`](scripts/WinCustomizer_Toolkit.ps1): menu tương tác cho các giai đoạn cleanup, unattend, Sysprep, capture và post-capture.
- [`templates/unattend.template.xml`](templates/unattend.template.xml): XML khởi đầu trung tính, không cài sẵn locale hay tùy chọn OOBE. Dùng menu 3 để tạo answer file thực tế.
- [`docs/PUBLISH_AND_RUN_VI.md`](docs/PUBLISH_AND_RUN_VI.md): publish lên GitHub và chạy từ URL Raw.
- [`docs/REFERENCES.md`](docs/REFERENCES.md): hướng dẫn ManHPC và tài liệu Microsoft.
- [`docs/SOURCE_AUDIT_VI.md`](docs/SOURCE_AUDIT_VI.md): đối chiếu trình tự các bước, answer-file passes và các giới hạn tự động hóa.

## Chạy toolkit

Cần Windows PowerShell 5.1 trở lên, chạy bằng quyền Administrator. Đọc mã trước khi chạy, nhất là khi tải qua Internet.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\scripts\WinCustomizer_Toolkit.ps1
```

Toolkit tạo hai answer file tách biệt: menu 3 tạo `unattend.xml` cho Sysprep/OOBE; post-capture task 16 tạo `autounattend.xml` với pass `windowsPE` và tùy chọn `oobeSystem\Shell-Setup\OOBE\ProtectYourPC`. `autounattend.xml` phải đặt ở gốc media cạnh `setup.exe`. Task 16 có preset chọn Windows 10/11 Pro, nhập key riêng hoặc bỏ ProductKey; key dùng chọn edition không tự kích hoạt Windows. Tùy chọn `ProtectYourPC` bật/tắt Express settings cũ; nó không điều khiển từng công tắc Privacy của Windows 11. Menu 3 hỏi và bắt buộc có `UILanguage`, `SystemLocale`, `UserLocale` (vùng/quốc gia) và `InputLocale` (bàn phím); timezone và fallback là tùy chọn. Menu 3 có thể tạo một local account trong `UserAccounts`, luôn trong nhóm `Administrators` để thiết bị còn tài khoản quản trị khi OOBE bỏ qua bước tạo account; nếu không chọn, OOBE sẽ yêu cầu tạo hoặc đăng nhập account thủ công. Không dùng `SkipMachineOOBE` hoặc các thiết lập Wi-Fi.

Wizard hỏi riêng `UILanguage`, `SystemLocale`, `UserLocale` (mã vùng/quốc gia cùng định dạng, ví dụ `vi-VN`), `InputLocale` (bàn phím), `UILanguageFallback` tùy chọn, `TimeZone`, OOBE choices và tùy chọn tạo local account. Giá trị mặc định là cấu hình Windows hiện tại; nhấn Enter sẽ ghi giá trị mặc định. Bốn giá trị locale/ngôn ngữ/bàn phím bắt buộc để trả lời cấu hình ngôn ngữ/vùng trong OOBE; `TimeZone`/`UILanguageFallback` có thể bỏ. OOBE chưa được cấu hình hết không tự biến mất; Microsoft khuyên không dùng `SkipMachineOOBE`. Cần chọn locale có trong image và kiểm tra answer file bằng Windows SIM trước final Sysprep.

## Bảo mật và giới hạn

- Lệnh `irm ... | iex` thực thi mã tải từ URL với quyền của phiên PowerShell hiện tại. Nên tải bản gắn tag, đọc mã, kiểm tra hash qua kênh tin cậy rồi mới chạy.
- Nếu chọn tạo local account, `unattend.xml` chứa tên user và password được encode Base64 (`PlainText=false`); Base64 không phải mã hóa bảo mật. Không commit hoặc chia sẻ answer file tạo ra.
- `CopyProfile`, Start layout và app associations không sao chép mọi cài đặt hay ứng dụng. Kiểm tra lại trên đúng bản Windows cần triển khai.
- Chuẩn WinPE thường không có PowerShell mặc định. Nếu không có PowerShell, capture thủ công bằng DISM từ Command Prompt; xem hướng dẫn để biết mẫu lệnh.
