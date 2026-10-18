# Windows Customizer

Toolkit PowerShell hỗ trợ chuẩn bị máy Windows tham chiếu, tạo answer file cho Sysprep, capture WIM và đóng gói lại ISO.

## Thành phần

- [`scripts/WinCustomizer_Toolkit.ps1`](scripts/WinCustomizer_Toolkit.ps1): menu tương tác gồm dọn dẹp/xuất cấu hình, tạo `unattend.xml`, chạy Sysprep và đóng gói ISO bằng AnyBurn CLI.
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
- Mặc định không bật AutoLogon, không tạo mật khẩu trống, không lưu thông tin Wi-Fi và không dùng `SkipMachineOOBE`/`BypassNRO`.
- `CopyProfile`, association mặc định và Start layout không bảo đảm sao chép mọi cài đặt hay ứng dụng. Kiểm tra lại trên đúng bản Windows sẽ triển khai.
- Lệnh tải `irm ... | iex` thực thi ngay nội dung URL với quyền của PowerShell hiện tại. Nên ưu tiên tải bản gắn tag, đọc mã, rồi mới chạy.

Xem [`docs/BUILD_GUIDE_VI.md`](docs/BUILD_GUIDE_VI.md) và [`docs/PUBLISH_AND_RUN_VI.md`](docs/PUBLISH_AND_RUN_VI.md) để biết đầy đủ các bước.
