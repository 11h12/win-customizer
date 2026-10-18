# Hướng dẫn tạo Windows Custom ISO

> Quy trình tham khảo cho Windows 10/11 x64, theo hướng Audit Mode → Sysprep → WinPE → DISM → ISO. Hãy làm trên máy ảo hoặc máy tham chiếu riêng, không dùng máy production.

## 1. Chuẩn bị máy tham chiếu

1. Tạo máy ảo/máy thử nghiệm và cài Windows từ ISO chính thức. Đảm bảo edition và kiến trúc phù hợp với mục tiêu triển khai.
2. Vào Audit Mode bằng `Ctrl` + `Shift` + `F3` tại OOBE. Windows đăng nhập bằng built-in Administrator và khởi động lại vào Audit Mode.
3. Cài ứng dụng, cập nhật Windows, cấu hình giao diện và các thiết lập muốn đưa vào profile mặc định. Hoàn tất cập nhật và khởi động lại cho đến khi Windows Update không còn yêu cầu restart.
4. Dùng built-in Administrator để cấu hình profile nếu dự định bật `CopyProfile`. Không tạo tài khoản tạm và không đăng nhập bằng domain account.
5. Nếu image chỉ dành cho cùng một model/phần cứng, có thể giữ driver bằng `PersistAllDeviceInstalls`. Khi script hỏi ở bước tạo answer file, chọn `Yes` chỉ trong trường hợp đó; nếu triển khai cho nhiều model hoặc chưa chắc, chọn `No`. Thiết lập này không thay thế quy trình quản lý driver.

**Không tạo user tạm trong giai đoạn này.** User tạm tạo thêm profile và có thể làm `CopyProfile` lấy nhầm profile hoặc khiến Sysprep không validate được image. Built-in `Administrator` trong Audit Mode là tài khoản dùng để cài đặt và tùy chỉnh image.

Nếu Windows Update yêu cầu restart trước khi hoàn tất tùy chỉnh, khi máy quay lại màn hình OOBE hãy nhấn lại `Ctrl` + `Shift` + `F3` để vào Audit Mode. Không tạo user cuối cùng trước khi capture.

## 2. Dọn dẹp và xuất cấu hình

Mở Windows PowerShell bằng quyền Administrator, vào thư mục repository rồi chạy:

```powershell
& .\scripts\WinCustomizer_Toolkit.ps1
```

Chọn mục `1`. Script dọn nội dung Temp và cache tải Windows Update, sau đó xuất:

- Association ứng dụng mặc định tại `C:\ProgramData\WinCustomizer\Exports\AppAssociations.xml`.
- Start layout tại `C:\ProgramData\WinCustomizer\Exports\StartLayout.json` nếu lệnh `Export-StartLayout` có trên hệ thống.

Các file export là dữ liệu tham khảo để kiểm tra/triển khai riêng. Việc xuất file không tự áp dụng association hoặc đảm bảo Start layout được giữ trong mọi bản Windows.

Script hỏi riêng trước khi chạy `DISM /StartComponentCleanup /ResetBase`. Chỉ chọn đồng ý khi đã quyết định không cần gỡ các bản cập nhật đã cài trên máy tham chiếu; `/ResetBase` làm mất khả năng uninstall các update hiện có.

## CopyProfile là gì?

`CopyProfile` lấy hồ sơ của tài khoản đang đăng nhập trong Audit Mode (thông thường là built-in Administrator) và dùng nó làm mẫu cho các tài khoản mới khi image được bung ra. Nó chạy ở pass `specialize` khi Sysprep xử lý answer file:

```xml
<settings pass="specialize">
  <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
    <CopyProfile>true</CopyProfile>
  </component>
</settings>
```

Trong Audit Mode, bạn có thể cấu hình những thứ thuộc trải nghiệm cá nhân của profile, chẳng hạn:

- hình nền, theme, màu sắc, font và một số tùy chọn Explorer;
- shortcut trên Desktop, thư mục và shortcut trong Start Menu của profile;
- một số tùy chọn ứng dụng và giao diện lưu trong profile người dùng;
- Favorites và một số thiết lập cá nhân tương ứng.

`CopyProfile` không sao chép nguyên tài khoản Administrator, SID, mật khẩu, dữ liệu riêng, lịch sử trình duyệt hay trạng thái đăng nhập. Ứng dụng và driver phải được cài riêng trong image; chúng không phải là nội dung được `CopyProfile` nhân bản từ profile. Microsoft cũng nêu rõ Start menu/taskbar pin, Default Apps và một số thiết lập được mã hóa theo từng người dùng có thể không được giữ hoặc sẽ bị Windows đặt lại. Hãy dùng cơ chế Start layout, DISM association, Group Policy hoặc script riêng cho các phần đó. [Microsoft: CopyProfile](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/customize-the-default-user-profile-by-using-copyprofile?view=windows-11)

Khi chuẩn bị profile để CopyProfile:

1. Chỉ đăng nhập bằng built-in Administrator; không dùng domain account.
2. Xóa mọi tài khoản tạm khác trước khi chạy Sysprep để Windows không chọn nhầm profile.
3. Không lưu tài liệu cá nhân, mật khẩu, token, khóa API hoặc dữ liệu công việc trong profile.
4. Cấu hình xong thì không tiếp tục sử dụng image như máy thường; hãy chạy Sysprep rồi capture.

Vì vậy, ở giai đoạn hiện tại bạn chỉ cần cài app/driver và tùy chỉnh giao diện trong Audit Mode. Chưa cần tạo user cuối cùng. User cuối cùng sẽ được tạo ở OOBE theo answer file, và profile mới sẽ lấy các thiết lập được CopyProfile giữ lại.

## 3. Tạo answer file

Chọn mục `2`. Nhập tên và mật khẩu mới cho tài khoản local Administrators được tạo ở OOBE. Không dùng mật khẩu trống hoặc mật khẩu dùng chung giữa các máy.

Script tạo:

```text
C:\Windows\System32\Sysprep\unattend.xml
```

Answer file bật `CopyProfile` ở pass `specialize`, có thể giữ driver theo lựa chọn phần cứng và khai báo local admin ở pass `oobeSystem`. Mật khẩu trong XML được biểu diễn dưới dạng Base64 để Windows Setup nhận `PlainText=false`; Base64 có thể giải mã ngược và không bảo vệ mật khẩu. Giữ ACL của file hạn chế, không đưa file vào GitHub. Windows Setup có thể cache answer file trong Panther; xóa các answer file còn chứa thông tin nhạy cảm trước khi bàn giao image, sau khi những pass cần thiết đã chạy.

Mặc định script không bật AutoLogon. AutoLogon nhiều lần hoặc tài khoản admin không mật khẩu làm lộ quyền truy cập khi image bị phát tán. Nếu lab cô lập thực sự cần AutoLogon, hãy thêm có chủ đích bằng Windows System Image Manager (Windows SIM), giới hạn số lần đăng nhập và kiểm tra việc xóa thông tin sau triển khai.

Các mục OOBE được cấu hình riêng thay vì dùng `SkipMachineOOBE`, mục Microsoft khuyến nghị không dùng để tự động hóa OOBE. Script không đặt `BypassNRO`: đây không phải cấu hình triển khai ổn định. Các trang không được cấu hình vẫn có thể xuất hiện; kiểm tra answer file bằng Windows SIM đúng catalog/bản Windows trước khi dùng.

## 4. Chạy Sysprep

1. Hoàn tất tùy biến và cập nhật. Chạy mục `1` để cleanup, mục `2` để tạo `unattend.xml`, rồi ngắt mạng theo quy trình vận hành của bạn trước khi chốt image.
2. Chọn mục `3`, xác nhận bằng cách gõ `SYSPREP`. Máy sẽ chạy:

   ```text
   sysprep.exe /generalize /oobe /shutdown /unattend:C:\Windows\System32\Sysprep\unattend.xml
   ```

3. Sau khi máy tắt, khởi động trực tiếp từ USB **Windows PE (WinPE)**. Không khởi động lại Windows đã Sysprep trước khi capture. Quy trình capture của Microsoft dùng WinPE; lệnh `reagentc /boottore` vào WinRE trong ghi chú ban đầu đã được bỏ khỏi script.
4. Trong WinPE, xác định đúng phân vùng Windows và ổ lưu trữ đích. Chữ cái ổ đĩa có thể khác so với Windows đang chạy:

   ```text
   diskpart
   list volume
   select volume <số-volume-Windows>
   assign letter=W
   exit
   dir W:\Windows
   ```

   Kiểm tra `W:\Windows` là Windows tham chiếu và ổ đích còn đủ dung lượng. Không lưu WIM vào phân vùng đang capture.
5. Capture image, thay `D:` bằng ổ đĩa ngoài của bạn:

   ```text
   dism /Capture-Image /ImageFile:D:\install.wim /CaptureDir:W:\ /Name:"Windows_Custom" /Description:"Custom Windows image" /Compress:max /CheckIntegrity /Verify
   ```

6. Kiểm tra index và edition trong WIM:

   ```text
   dism /Get-WimInfo /WimFile:D:\install.wim
   ```

## 5. Capture WIM bằng toolkit trong WinPE

Sau khi Sysprep đã tắt máy, boot USB WinPE. Chạy toolkit bằng PowerShell nếu WinPE của bạn có PowerShell, chọn mục `4`. Toolkit sẽ liệt kê volume, yêu cầu chọn:

- ổ chứa Windows tham chiếu, phải có `Windows\System32`;
- ổ lưu WIM, bắt buộc khác ổ source;
- đường dẫn file `.wim` hoặc `.esd` đầu ra. Nếu chọn `.esd`, toolkit capture WIM trung gian rồi dùng `DISM /Export-Image /Compress:recovery` để chuyển đổi.

Toolkit chạy `DISM /Capture-Image` với `/Compress:max /CheckIntegrity /Verify`, sau đó chạy `/Get-WimInfo` để kiểm tra index. Nếu chọn ESD, image được nén lại bằng `/Compress:recovery`. Nếu WinPE không có PowerShell, dùng lệnh DISM thủ công:

```text
dism /Capture-Image /ImageFile:D:\install.wim /CaptureDir:W:\ /Name:"Windows_Custom" /Description:"Custom Windows image" /Compress:max /CheckIntegrity /Verify
dism /Get-WimInfo /WimFile:D:\install.wim
```

## 6. Thay WIM và đóng gói ISO

1. Khởi động lại vào Windows đã cài AnyBurn. Không boot lại máy tham chiếu đã Sysprep để sử dụng tiếp làm máy thường.
2. Chạy toolkit, chọn mục `5`, nhập ISO gốc, WIM/ESD vừa capture và đường dẫn ISO đầu ra. Script hỗ trợ image `.wim` hoặc `.esd`; ISO gốc có `sources\install.wim` hoặc `sources\install.esd`. ISO dùng bộ `install*.swm` chia phần cần quy trình riêng.
3. Toolkit dùng AnyBurn CLI theo mẫu lệnh sau để thay image trong thư mục `sources`:

   ```text
   abcmd.exe -edit <Windows_Original.iso> -delete "\sources\install.wim" -add <install.wim> "\sources\" -save <Windows_Custom.iso>
   ```

   Script sẽ thay image cũ bằng đúng file WIM/ESD bạn chỉ định. Đối chiếu tham số với phiên bản `abcmd.exe` đã cài nếu CLI báo lỗi.
4. Mount ISO đầu ra và xác nhận `sources\install.wim` mở được; sau đó boot thử ISO trong máy ảo (bao gồm kiểm tra OOBE, account, driver, activation và Windows Update) trước khi phát hành.

## Quy trình ngắn

```text
Audit Mode → tùy biến + cập nhật → export/cleanup → answer file
→ ngắt mạng → Sysprep /generalize /oobe /shutdown
→ boot WinPE → capture WIM → thay WIM vào ISO → test trong VM
```
