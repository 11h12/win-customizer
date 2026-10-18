# Quy trình dựng Windows image và hoàn thiện ISO

Toolkit tự động các lệnh Windows/DISM/copy có thể kiểm tra bằng exit code và file đầu ra. Thao tác giao diện AnyBurn/UltraISO và map đĩa ảo cần người dùng làm; script có checkpoint riêng cho từng thao tác và chỉ ghi `SUCCESS` sau khi người dùng nhập `DONE`. Script không tạo, khởi động, snapshot hoặc revert máy ảo.

## 1. Cài Windows và chuẩn bị tài khoản dùng để cấu hình

1. Cài Windows từ ISO gốc và hoàn thành toàn bộ OOBE bằng một tài khoản local tạm có quyền Administrator. Không nhấn `Ctrl+Shift+F3` tại màn hình OOBE đầu tiên trong quy trình này.
2. Trong tài khoản tạm đó, cài driver, Windows Features, ứng dụng, font và phần mềm cần đưa vào image. Cấu hình Start, Default apps và ứng dụng cần thiết.
3. Chạy Windows Update, khởi động lại mỗi khi được yêu cầu, rồi kiểm tra lại đến khi không còn cập nhật đang chờ.
4. Khi vẫn đăng nhập bằng tài khoản đã cấu hình Default apps/Start, chạy toolkit bằng Administrator và chọn **1. Export Default Apps/Start layout trước khi vào Audit**. Làm trước khi xóa profile tạm để DISM export đúng lựa chọn của tài khoản đó.

Menu 1 lưu vào `WinCustomizer\Exports` trên volume nhãn `BACKUP` nếu tìm thấy. Có thể đổi đường dẫn khi được hỏi. Các file gồm:

- `AppAssociations.xml`
- Windows 10: `LayoutModification.xml`; Windows 11: `StartLayout.json` nếu `Export-StartLayout` có trên hệ thống.

Ghi lại đường dẫn đầy đủ. Nếu ổ BACKUP chưa có, chọn một thư mục được giữ lại và copy file ra host trước khi xóa user tạm. File Start layout ở đây chỉ là bản export/backup; toolkit không nhập nó vào WIM. Bài ManHPC chỉnh `DefaultLayouts.xml` trong Windows đang dựng trước capture, nên nếu cần giữ Start pins thì phần đó vẫn phải cấu hình trong image trước final Sysprep.

## 2. Vào Audit Mode sau khi OOBE đã hoàn tất

1. Từ Windows đã setup, chạy `C:\Windows\System32\Sysprep\Sysprep.exe` bằng quyền Administrator.
2. Chọn **Enter System Audit Mode** và **Reboot**. Sau khi reboot, Windows đăng nhập vào built-in Administrator; trạng thái tài khoản có thể hiện `Disabled` trong Local Users and Groups khi đang ở Audit Mode.
3. Xóa profile tài khoản tạm bằng **System Properties → Advanced → User Profiles → Settings**, sau đó xóa tài khoản tạm trong `lusrmgr.msc`. Kiểm tra `C:\Users` để chắc profile đã được bỏ.
4. Nếu cần Desktop shortcut cho mọi user, đặt shortcut tại `C:\Users\Public\Desktop`.
5. Đặt shortcut portable apps dùng chung tại `C:\ProgramData\Microsoft\Windows\Start Menu\Programs`. Trong menu 2, toolkit có thể mở thư mục này để bạn tự thêm shortcut.
6. Chạy menu **2. Cleanup Windows trong Audit Mode**. Toolkit yêu cầu SID built-in Administrator kết thúc `-500`, dọn Temp/Windows Update theo từng task, hỏi có chạy `StartComponentCleanup /ResetBase` hay không, rồi chạy task riêng `AnalyzeComponentStore`. `ResetBase` khiến các bản cập nhật hiện có không thể gỡ.

## 3. Tạo answer file cho Sysprep/OOBE

Chạy menu **3. Tạo Sysprep `unattend.xml`**. File làm việc được ghi tại:

```text
C:\Windows\System32\Sysprep\unattend.xml
```

Wizard hỏi từng cấu hình:

- `CopyProfile` và `PersistAllDeviceInstalls`.
- Kiến trúc answer file Sysprep tự lấy từ Windows đang chạy (`amd64` hoặc `x86`); script từ chối nếu file không khớp kiến trúc hệ điều hành.
- `UILanguage`: ngôn ngữ giao diện có trong image. Wizard kiểm tra ngôn ngữ này nằm trong danh sách language pack đang cài trên máy dựng.
- `SystemLocale`: locale cho ứng dụng non-Unicode.
- `UserLocale`: mã ngôn ngữ-vùng dùng làm quốc gia/vùng và định dạng ngày, giờ, số, tiền tệ trong OOBE; ví dụ `vi-VN` là Việt Nam, `en-US` là Hoa Kỳ. Đây là setting vùng trong answer file, không phải một trường `GeoID` riêng.
- `InputLocale`: bàn phím/IME; có thể nhập nhiều layout ngăn cách bằng `;`, ví dụ `0409:00000409;042A:0000042A`. Wizard kiểm tra cú pháp locale và layout ID trong registry của Windows đang dựng.
- `UILanguageFallback` nếu UI language chỉ được dịch một phần.
- `TimeZone`, ví dụ `SE Asia Standard Time`.
- Có tạo một local account từ `UserAccounts` trong OOBE không; nếu có, wizard hỏi tên và mật khẩu nhập hai lần, rồi thêm tài khoản vào `Administrators`. Microsoft lưu ý rằng khi `UserAccounts` tạo tài khoản trong answer file thì luồng tạo user trong OOBE có thể bị bỏ qua; giữ tài khoản này trong Administrators tránh hoàn tất setup mà không có tài khoản quản trị. Nếu muốn user thường, hãy tạo tài khoản đó sau khi đăng nhập admin. Không áp đặt độ dài tối thiểu 12 ký tự; chính sách mật khẩu Windows vẫn có thể từ chối mật khẩu không đạt yêu cầu của image.
- Tùy chọn ẩn EULA, màn hình đăng nhập Microsoft account, đăng ký OEM và lựa chọn `ProtectYourPC`. `HideEULAPage` mặc định không bật; Microsoft giới hạn setting này cho OEM/System Builder dùng để kiểm thử trước khi xuất xưởng.

Các giá trị trong ngoặc vuông là cấu hình hiện tại của Windows đang dựng; nhấn Enter dùng đúng giá trị đó. `UILanguage`, `SystemLocale`, `UserLocale` và `InputLocale` bắt buộc, không thể nhập `NONE`, để trả lời cấu hình ngôn ngữ/vùng/bàn phím trong OOBE. `TimeZone` hoặc `UILanguageFallback` có thể bỏ. `UserLocale` là thiết lập quốc gia/vùng và định dạng; nó khác ngôn ngữ giao diện (`UILanguage`) và bàn phím (`InputLocale`). Chỉ chọn locale có trong image.

Nếu chọn tạo local account trong answer file thì Windows tạo account đó trong OOBE; nếu không chọn, người cài đặt tạo hoặc đăng nhập account thủ công. `HideOnlineAccountScreens` chỉ ẩn trang đăng nhập Microsoft account, không tự tạo user. `UserAccounts` tạo local account đã khai báo trong OOBE. Cấu hình locale, account và các lựa chọn OOBE giúp Windows tự áp dụng các trang tương ứng; điều này không đồng nghĩa bỏ toàn bộ OOBE. Microsoft quy định trang nào không có setting trong answer file thì trang đó vẫn có thể hiện. Theo lựa chọn của bạn, toolkit không tạo setting Wi-Fi; bước mạng không được tự động hóa.

`unattend.xml` và `autounattend.xml` phục vụ hai giai đoạn khác nhau:

- `autounattend.xml`: thường chứa pass `windowsPE`, đặt ở gốc media cạnh `setup.exe` để Windows Setup đọc khi bắt đầu cài.
- `unattend.xml`: file toolkit tạo cho các pass Sysprep như `specialize` và `oobeSystem`, đặt trong thư mục Sysprep của Windows đang tham chiếu.

Script đặt từng setting theo component/pass Microsoft định nghĩa:

| File/pass | Component | Setting toolkit có thể ghi |
|---|---|---|
| `autounattend.xml` / `windowsPE` | `Microsoft-Windows-Setup` → `UserData` | `AcceptEula`; tùy chọn `ProductKey` → `Key` và `WillShowUI` để Setup chọn edition |
| `autounattend.xml` / `oobeSystem` (tùy chọn) | `Microsoft-Windows-Shell-Setup` → `OOBE` | Tùy chọn `ProtectYourPC` để bật/tắt Express settings; không cấu hình từng privacy toggle mới của Windows 11 |
| `unattend.xml` / `generalize` | `Microsoft-Windows-PnpSysprep` | Tùy chọn `PersistAllDeviceInstalls=true`, chỉ cho phần cứng đích giống hệt |
| `unattend.xml` / `specialize` | `Microsoft-Windows-Shell-Setup` | Tùy chọn `CopyProfile=true` và `TimeZone` |
| `unattend.xml` / `oobeSystem` | `Microsoft-Windows-International-Core` | `InputLocale`, `SystemLocale`, `UILanguage`, tùy chọn `UILanguageFallback`, `UserLocale` |
| `unattend.xml` / `oobeSystem` | `Microsoft-Windows-Shell-Setup` | Tùy chọn `UserAccounts`; `OOBE` flags được wizard hỏi |

Không đặt ProductKey chọn edition trong `Shell-Setup\ProductKey`: setting đó dành cho activation ở pass khác. Không đặt `CopyProfile` ở OOBE, `PersistAllDeviceInstalls` ở specialize, hay locale trong component Shell-Setup. Toolkit final-check pass/component trước khi cho chạy Sysprep.

Toolkit tạo cả hai file bằng hai tác vụ riêng: menu 3 tạo file thứ hai (`unattend.xml`), post-capture task 16 tạo `autounattend.xml`. File thứ hai trả lời EULA và tùy chọn chọn edition; tùy chọn `ProtectYourPC` ghi riêng pass `oobeSystem` để điều khiển Express settings. Không tự chọn ổ/partition hoặc ngôn ngữ giao diện Windows Setup. Không dùng `SkipMachineOOBE` hoặc `SkipUserOOBE`; Microsoft khuyến nghị cấu hình các setting tương ứng. Toolkit không tạo cấu hình Wi-Fi. `HideLocalAccountScreen` không có trong file Windows client vì setting này chỉ áp dụng Windows Server.

Trước khi chạy Sysprep, mở Windows SIM với catalog đúng bản Windows/architecture, nạp answer file và xác thực. Toolkit cũng kiểm tra root/namespace, component, pass, architecture, setting trùng, locale/timezone, tài khoản/mật khẩu, setting chỉ dành cho Server và các cờ bị cấm; các kiểm tra này không thay cho Windows SIM xác thực bằng catalog đúng bản Windows.

### Chọn edition Windows khi cài từ ISO

`autounattend.xml` ở pass `windowsPE` dùng `Microsoft-Windows-Setup\UserData\ProductKey\Key` để Windows Setup chọn edition theo key. Đây là file khác với `unattend.xml` trong thư mục Sysprep. Trong post-capture menu, chọn **16. Tạo autounattend.xml chọn edition và Express settings OOBE**:

1. Chọn preset generic setup key Windows 10/11 Pro, nhập key của bạn, hoặc bỏ ProductKey.
2. Chọn cách xử lý Express settings trong OOBE: `1` bật, `3` tắt, Enter bỏ setting để Windows hỏi người dùng. Setting này không trả lời riêng từng công tắc Privacy trên Windows 11.
3. Chọn architecture của Windows Setup và nơi lưu file. Tên phải đúng `autounattend.xml`.
4. Khi chọn menu **13. Thay image trong ISO**, nhập đường dẫn file này. Script thêm một checkpoint riêng để chép nó vào **gốc ISO**, cùng cấp với `setup.exe`, rồi mới Save As ISO mới.
5. Chọn **14. Verify ISO** và cung cấp file nguồn để kiểm tra `autounattend.xml` trong ISO có cùng SHA-256.

Key preset Pro chỉ chọn edition, không kích hoạt Windows. Hệ thống vẫn cần digital license hoặc license hợp lệ tương ứng. Nếu nhập key cá nhân, XML lưu key dạng rõ; không đưa file này lên GitHub, không commit và không chia sẻ. `.gitignore` đã loại trừ file answer được tạo và file backup cùng tên.

Key chỉ phân biệt edition. Nếu `install.wim` có nhiều index cùng edition Pro nhưng muốn chọn đúng một index cụ thể, cần cấu hình `ImageInstall\OSImage\InstallFrom\MetaData` theo `/IMAGE/INDEX`, `/IMAGE/NAME` hoặc `/IMAGE/DESCRIPTION`; task 16 hiện chưa tạo bộ lọc index này. Nếu bỏ ProductKey, Windows Setup có thể hỏi chọn edition hoặc dùng edition mặc định trong media. `autounattend.xml` do task 16 sinh trả lời EULA, ProductKey và tùy chọn `ProtectYourPC`; không tự chọn ổ/partition hoặc tự động hóa tất cả trang Windows Setup. Windows 11 có màn hình Privacy riêng với nhiều lựa chọn; tài liệu answer-file Microsoft hiện dùng ở đây không cung cấp setting để đặt từng lựa chọn đó. Để nguyên phần này cho người cài chọn trong OOBE.

Nếu nhập đường dẫn backup, file backup cũng chứa thông tin account/password đã encode. `PlainText=false`/Base64 không phải mã hóa bảo mật. Không commit hoặc chia sẻ answer file; chỉ giữ bản backup ở nơi riêng tư và xóa bản chứa mật khẩu sau khi triển khai.

## 4. Chạy final Sysprep

Sau khi Windows SIM xác thực answer file, kiểm tra không còn cập nhật chờ restart và đang ở Audit Mode. Chọn menu **4. Chạy final Sysprep**. Toolkit kiểm tra:

1. Tài khoản hiện tại là built-in Administrator (SID-RID `500`).
2. Có `C:\Windows\System32\Sysprep\unattend.xml` và XML đọc được.
3. Các setting bị cấm như `SkipMachineOOBE`, `SkipUserOOBE`, `AutoLogon`, `BypassNRO`, Wi-Fi và `HideLocalAccountScreen` không xuất hiện.
4. Bạn gõ chính xác `SYSPREP` để xác nhận chạy `/generalize /oobe /shutdown`.

Khi Sysprep tắt máy, không boot Windows tham chiếu trở lại. Boot WinPE/USB để capture.

## 5. Capture trong WinPE

Menu **5. Capture WIM/ESD** cần Windows PowerShell 5.1 trong WinPE. WinPE tiêu chuẩn có thể không cài PowerShell; trong trường hợp đó mở Command Prompt, dùng `diskpart` → `list volume` → `exit`, xác định đúng volume Windows và BACKUP, sau đó chạy DISM thủ công. Ví dụ dưới đây chỉ là mẫu; thay ký tự volume theo kết quả thực tế:

```cmd
Dism /Capture-Image /ImageFile:D:\install.wim /CaptureDir:W:\ /Name:"Windows_Custom" /Description:"Custom Windows image" /Compress:fast /CheckIntegrity /Verify
```

Không dựa vào ký tự ổ đĩa đã thấy trong Windows trước đó; WinPE có thể gán chữ khác. Capture chỉ sau khi Sysprep đã shutdown. Chờ DISM báo hoàn tất, rồi kiểm tra file/index bằng `Dism /Get-WimInfo /WimFile:D:\install.wim`.

Nếu chọn `.esd` trong toolkit, script capture ra WIM trung gian, export sang ESD với `/Compress:recovery`, xóa WIM trung gian sau khi ESD được tạo, rồi kiểm tra index. Đây là các task riêng có trạng thái/tiến trình riêng.

## 6. Map BACKUP và copy file sang host

Sau khi capture xong và máy tham chiếu đã tắt:

1. Chọn menu **6. Post-capture** → **1. Map BACKUP.vmdk**. Trên host, map file `BACKUP.vmdk` trong VMware Workstation bằng **Map Virtual Disk**. Đây là thao tác host thủ công; không mở/boot lại máy tham chiếu.
2. Xác nhận drive letter vừa map. Nếu export mặc định trên volume `BACKUP`, ví dụ volume được gán `R:`, file export là `R:\WinCustomizer\Exports\AppAssociations.xml` và layout nằm cùng thư mục.
3. Chọn **2. Copy exports**. Toolkit copy vào file staging, so kích thước và SHA-256, rồi mới publish; nếu đích đã có file cũ, file cũ được giữ thành `.previous.<id>`. Mặc định đích là:

   ```text
   D:\LAB\source\21H1\AppAssociations\x86\AppAssociations.xml
   ```

   Có thể đổi build/architecture. Copy `StartLayout.json` hoặc `LayoutModification.xml` là tùy chọn riêng; script giữ nguyên tên file.

4. Chọn **3. Copy capture image**. Toolkit copy vào file staging có thanh tiến trình, kiểm tra kích thước rồi mới publish; nếu đích đã có file cũ, file cũ được giữ thành `.previous.<id>`. Mặc định đích là:

   ```text
   D:\LAB\source\21H1\x86\install.wim
   ```

   Nếu nguồn là ESD, file đích giữ đuôi `.esd`. Để làm image thứ hai, capture/copy WIM vào `D:\LAB\source\21H1\x86-2\install.wim`. Copy dùng thanh tiến trình và kiểm tra kích thước nguồn/đích.

5. Chọn **4. DISM Get-WimInfo** để xem index, edition, architecture, name và description. Chọn index đúng trước khi sửa metadata.

## 7. Sửa metadata, ghép image và associations

### Image đơn

1. Chọn **5. Sửa metadata** cho đúng file `.wim` và index. Nhập Image Name, Description và SKU Flags (ví dụ `Professional`, `Core` hoặc `Enterprise`). Nếu có `wimlib-imagex`, toolkit cập nhật và đọc lại metadata; nếu không, chọn GImageX/NTLite rồi tự kiểm tra tab Info. Không sửa metadata trên nhầm index.
2. Chọn **13. Thay image trong ISO**. Toolkit mở AnyBurn/UltraISO. Theo từng checkpoint, mở ISO gốc trong chế độ Edit, xóa đúng `install.wim`/`install.esd` trong folder đã chỉ định, thêm image mới cùng tên file vào đúng folder, rồi Save As sang ISO khác.
3. Chọn **14. Verify ISO** để mount ISO đầu ra và chạy `DISM /Get-WimInfo` trên install image bên trong.

### Nhiều image trong một `install.wim`

Lặp capture/copy/metadata cho image tiếp theo dưới dạng **WIM**. Ví dụ: base ở `D:\LAB\source\21H1\x86\install.wim`, capture thứ hai ở `D:\LAB\source\21H1\x86-2\install.wim`. Chỉ chuyển sang ESD sau khi đã append và sửa tất cả index.

1. Chọn **4. Get-WimInfo** trên capture thứ hai; ghi lại source index.
2. Chọn **5. Sửa metadata** trên capture thứ hai và đặt description/SKU Flags đúng edition.
3. Chọn **6. Append image**: nhập capture WIM, source index, WIM đích đang có (ví dụ `D:\LAB\source\21H1\x86\install.wim`), tên image mới và đường dẫn backup. Toolkit đọc thông tin cả source/destination, hỏi xác nhận compression, copy WIM đích sang backup có tiến trình, verify backup bằng `Get-WimInfo`, rồi mới DISM export vào WIM đích. Source/destination phải cùng kiểu nén. Nếu append hoặc verify lỗi, có thể yêu cầu toolkit phục hồi từ backup.
4. Xem `Get-WimInfo` ở cuối task append để xác nhận index mới. Nếu cần, chạy lại task **5. Sửa metadata** trên index vừa thêm.
5. Chọn **7. Mount image**, nhập install.wim/index cần sửa và một thư mục mount rỗng (mặc định `C:\WinCustomizer\Mount`).
6. Chọn **8. Import AppAssociations** vào image đang mount. Dùng file ở đường dẫn đích mục 6.
7. Nếu Sysprep đã dùng `CopyProfile=true`, chọn **9. Cleanup registry Default profile**. Task xác nhận WIM còn mount, nạp `Users\Default\NTUSER.DAT`, dọn ba registry entries Microsoft nêu, rồi unload hive. Nếu không dùng CopyProfile thì bỏ qua. Nếu task báo lỗi hoặc hive không unload được, không COMMIT WIM.
8. Chọn **10. Verify associations** bằng DISM.
9. Chọn **11. Unmount image** và nhập `COMMIT` để lưu; chọn `DISCARD` sẽ hủy thay đổi. Đợi DISM unmount hoàn thành trước khi đóng hoặc di chuyển WIM.
10. Nếu muốn ESD, hoàn tất mọi sửa đổi và COMMIT WIM trước. Chọn **12. Export all indexes to ESD**; script export từng index riêng với `/Compress:recovery` và status/progress riêng. ESD được tạo ở file staging; script chỉ thay ESD đích sau khi tất cả index export và `Get-WimInfo` đều thành công. Nếu một index lỗi, file đích cũ vẫn được giữ nguyên và staging được giữ để kiểm tra.
11. Chọn **13. Thay image trong ISO** và dùng `install.wim` hoặc `install.esd` phù hợp. Với media AIO, nhập đúng folder như `\x64\sources\` hoặc `\x86\sources\`, không dùng mặc định `\sources\` nếu cấu trúc khác.
12. Chọn **14. Verify ISO** sau khi Save As.

AnyBurn và UltraISO chỉnh ISO bằng giao diện. Tài liệu CLI AnyBurn công khai không mô tả thao tác Edit ISO, nên toolkit không gọi switch CLI chưa được xác nhận. Mỗi thao tác giao diện có tên task và yêu cầu xác nhận hoàn thành.

## 8. Đối chiếu task trong post-capture

| Menu | Tác vụ | Kiểm tra/tiến trình |
|---|---|---|
| 1 | Map BACKUP.vmdk trên host | Hướng dẫn thủ công, yêu cầu xác nhận |
| 2 | Copy AppAssociations/Layout | Copy staging, kiểm tra kích thước và SHA-256; giữ file đích cũ |
| 3 | Copy install.wim/esd | Thanh tiến trình, kiểm tra kích thước staging; giữ file đích cũ |
| 4 | DISM Get-WimInfo | Mã thoát DISM |
| 5 | Sửa metadata | wimlib đọc lại hoặc xác nhận GImageX/NTLite |
| 6 | Backup rồi append image vào WIM hiện có | Thanh tiến trình backup/append, verify backup và Get-WimInfo sau append |
| 7 | Mount image | Trạng thái DISM |
| 8 | Import associations | Trạng thái DISM |
| 9 | Cleanup registry Default profile nếu dùng CopyProfile | Nạp/unload hive riêng; mỗi entry được xóa và kiểm tra riêng |
| 10 | Verify associations | Trạng thái DISM |
| 11 | Unmount image | COMMIT hoặc DISCARD; trạng thái DISM |
| 12 | Export từng index thành ESD | Mỗi index có tiến trình/status riêng; verify staging rồi publish, giữ file đích cũ |
| 13 | Edit ISO, remove/add, Save As | Mỗi thao tác GUI có checkpoint riêng |
| 14 | Mount ISO và Get-WimInfo | Mã thoát DISM, tự unmount ISO |
| 15 | Xóa source AppAssociations.xml trên BACKUP | So kích thước và SHA-256 nguồn/copy; hỏi xác nhận trước xóa |
| 16 | Tạo `autounattend.xml` cho chọn edition và Express settings OOBE | XML `windowsPE` và tùy chọn `oobeSystem\Shell-Setup\OOBE\ProtectYourPC`; chọn preset Pro, key riêng hoặc không key; file được thêm vào gốc ISO bằng task 13 |

Bài ManHPC kết thúc bằng việc test bộ cài mới. Toolkit không tự cài Windows hay điều khiển máy ảo; bước test cài đặt/kiểm tra Start, Desktop, ứng dụng mặc định vẫn do bạn thực hiện bên ngoài toolkit.

## Tham khảo

- [ManHPC — Rebuild bộ cài Windows, Phần 3](https://manhpc.com/huong-dan-rebuild-bo-cai-windows-phan-3/)
- [ManHPC — Tạo và cấu hình answer file, Phần 5](https://manhpc.com/huong-dan-tao-va-cau-hinh-file-tra-loi-tu-dong-unattend-xml-phan-5/)
- [Microsoft — Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe?view=windows-11)
- [Microsoft — Export or Import Default Application Associations](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/export-or-import-default-application-associations?view=windows-11)
- [Microsoft — DISM image management options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-image-management-command-line-options-s14?view=windows-10)
