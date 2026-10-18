# Đưa toolkit lên GitHub và chạy từ PowerShell

## 1. Tạo GitHub repository

1. Trên GitHub, tạo repository tên `win-customizer`. Nếu muốn máy khác tải script không cần đăng nhập, repository phải là **Public**.
2. Tạo repository rỗng, không tạo sẵn README hoặc `.gitignore` trên GitHub vì các file đó đã có trong repo local.
3. Từ thư mục local, commit các file hướng dẫn/script rồi thêm remote và push nhánh hiện tại:

   ```powershell
   git add .
   git commit -m "Add Windows customization toolkit"
   git remote add origin https://github.com/OWNER/win-customizer.git
   $branch = git branch --show-current
   git push -u origin $branch
   ```

   Thay `OWNER` bằng username/organization GitHub. Khi tạo bản phát hành, nên tạo tag (ví dụ `v2.4.0`) để URL tải không đổi theo commit mới.

## 2. Tạo URL Raw

Đường dẫn file trong repo là `scripts/WinCustomizer_Toolkit.ps1`. URL có dạng:

```text
https://raw.githubusercontent.com/OWNER/win-customizer/BRANCH/scripts/WinCustomizer_Toolkit.ps1
```

Thay `OWNER` và `BRANCH` bằng giá trị thật. Có thể dùng tag thay cho tên nhánh, ví dụ:

```text
https://raw.githubusercontent.com/OWNER/win-customizer/v2.4.0/scripts/WinCustomizer_Toolkit.ps1
```

Kiểm tra URL bằng trình duyệt trước. Nội dung phải bắt đầu bằng mã PowerShell, không phải trang HTML báo lỗi.

## 3. Cách khuyến nghị: tải, xem mã, rồi chạy

Mở PowerShell bằng quyền Administrator trên máy tham chiếu, thay URL bằng URL thật:

```powershell
$uri = 'https://raw.githubusercontent.com/OWNER/win-customizer/v2.4.0/scripts/WinCustomizer_Toolkit.ps1'
$file = Join-Path $env:TEMP 'WinCustomizer_Toolkit.ps1'
Invoke-WebRequest -Uri $uri -OutFile $file
Get-Content -LiteralPath $file
Get-FileHash -LiteralPath $file -Algorithm SHA256
```

Sau khi tự kiểm tra mã và hash với giá trị đã lấy từ kênh tin cậy, chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file
```

`Bypass` ở đây chỉ áp dụng cho tiến trình PowerShell vừa mở; execution policy không phải ranh giới bảo mật. Hash chỉ xác nhận nội dung nếu so sánh với hash nhận qua một kênh tin cậy.

## 4. Lệnh tiện lợi `irm | iex`

Chỉ dùng khi tin tưởng owner, repository, tag và đã kiểm tra mã nguồn của đúng phiên bản:

```powershell
irm 'https://raw.githubusercontent.com/OWNER/win-customizer/v2.4.0/scripts/WinCustomizer_Toolkit.ps1' | iex
```

`irm` tải nội dung, `iex` phân tích và thực thi ngay trong phiên PowerShell hiện tại. Nếu chạy PowerShell bằng quyền Administrator thì toàn bộ mã tải được có quyền Administrator. Không dùng URL trỏ tới nhánh phát triển nếu cần tái lập hoặc kiểm soát phiên bản.

### Chạy từ CMD

Thay URL placeholder trước khi chạy để dấu `<`/`>` không bị CMD hiểu là chuyển hướng:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/OWNER/win-customizer/v2.4.0/scripts/WinCustomizer_Toolkit.ps1' | iex"
```

## 5. Link rút gọn và cập nhật

Link TinyURL/Bitly/domain redirect chỉ chuyển hướng tới URL Raw; nó không xác minh mã và có thể bị đổi đích. Nếu dùng link rút gọn, giới hạn quyền sửa link và kiểm tra đích trước khi chạy.

Khi phát hành phiên bản mới:

1. Review thay đổi script và cập nhật hướng dẫn.
2. Tạo tag release mới.
3. Kiểm tra URL Raw theo tag và hash.
4. Thử trong máy ảo trước khi gửi lệnh cho máy khác.
