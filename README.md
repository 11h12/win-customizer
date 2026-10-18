# Windows Customizer

Toolkit PowerShell hỗ trợ chuẩn bị máy Windows tham chiếu, tạo answer file cho Sysprep, capture WIM và đóng gói lại ISO.

Quy trình chuẩn là: vào Audit Mode bằng `Ctrl+Shift+F3`, dùng built-in Administrator để cài driver/app/update và tùy chỉnh, không tạo user tạm; sau đó cleanup, tạo `unattend.xml`, chạy Sysprep, boot WinPE để capture WIM và cuối cùng đóng gói ISO.

## Thành phần

- [`scripts/WinCustomizer_Toolkit.ps1`](scripts/WinCustomizer_Toolkit.ps1): menu tương tác gồm dọn dẹp/xuất cấu hình, tạo `unattend.xml`, chạy Sysprep và đóng gói ISO bằng AnyBurn CLI.
- [`templates/unattend.template.xml`](templates/unattend.template.xml): mẫu XML an toàn không chứa mật khẩu. Mục 2 tạo file riêng tại thư mục Sysprep theo các lựa chọn của bạn.
- [`docs/BUILD_GUIDE_VI.md`](docs/BUILD_GUIDE_VI.md): quy trình dựng image từ Audit Mode đến kiểm tra ISO.
- [`docs/PUBLISH_AND_RUN_VI.md`](docs/PUBLISH_AND_RUN_VI.md): đưa script lên GitHub và chạy từ URL Raw.
- [`docs/REFERENCES.md`](docs/REFERENCES.md): tài liệu tham khảo chính thức.

## Bắt đầu

Yêu cầu Windows 10/11 x64, Windows PowerShell 5.1 chạy bằng quyền Administrator. Hãy đọc hướng dẫn dựng image trước và thực hành trên máy ảo hoặc máy thử nghiệm có thể khôi phục.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\scripts\WinCustomizer_Toolkit.ps1
```

Script không tự chạy các bước phá hủy: dọn Component Store, Sysprep (sẽ tắt máy) và thay WIM trong ISO đều cần thao tác xác nhận. Không dùng image thử nghiệm làm máy đang sử dụng.

## Bảo mật và giới hạn

- Script cần quyền Administrator. Hãy xem mã nguồn trước khi chạy, nhất là khi tải trực tiếp từ Internet.
- Mật khẩu local admin được hỏi lúc tạo answer file. Giá trị trong XML được mã hóa Base64 theo định dạng Windows SIM, **không phải mã hóa bảo mật**. File answer có thông tin nhạy cảm; không commit hoặc phát hành file đó.
- Mặc định không bật AutoLogon, không tạo mật khẩu trống và không dùng `SkipMachineOOBE`/`BypassNRO`.
- `CopyProfile`, association mặc định và Start layout không bảo đảm sao chép mọi cài đặt hay ứng dụng. Kiểm tra lại trên đúng bản Windows sẽ triển khai.
- Ứng dụng đã cài nằm trong WIM; `unattend.xml` không sao chép ứng dụng.
- Lệnh tải `irm ... | iex` thực thi ngay nội dung URL với quyền của PowerShell hiện tại. Nên ưu tiên tải bản gắn tag, đọc mã, rồi mới chạy.

Xem [`docs/BUILD_GUIDE_VI.md`](docs/BUILD_GUIDE_VI.md) và [`docs/PUBLISH_AND_RUN_VI.md`](docs/PUBLISH_AND_RUN_VI.md) để biết đầy đủ các bước.
