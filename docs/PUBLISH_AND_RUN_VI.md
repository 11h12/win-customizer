# Cập nhật toolkit trên GitHub và chạy từ PowerShell

Repository hiện tại: `11h12/win-customizer`, nhánh `main`.

## Cập nhật repository

Trong thư mục checkout repository, review thay đổi rồi commit/push:

```powershell
git status
git diff
git add README.md docs scripts templates
git commit -m "Update Windows build workflow and unattend wizard"
git push origin main
```

URL Raw của script trên nhánh `main`:

```text
https://raw.githubusercontent.com/11h12/win-customizer/main/scripts/WinCustomizer_Toolkit.ps1
```

Alias rút gọn do bạn cấu hình là:

```text
https://maclife.vn/wincustomizer
```

Alias phải chuyển hướng tới file Raw mới nhất trên GitHub. Sau khi push, mở URL Raw/alias trong trình duyệt và xác nhận phần đầu hiển thị mã PowerShell, không phải trang HTML hoặc lỗi 404. Nếu alias đang thêm query như `?v=latest`, GitHub raw phải trả nội dung file với query đó.

## Cách an toàn: tải, xem mã, rồi chạy

Mở PowerShell bằng quyền Administrator trên máy dựng image:

```powershell
$uri = 'https://raw.githubusercontent.com/11h12/win-customizer/main/scripts/WinCustomizer_Toolkit.ps1'
$file = Join-Path $env:TEMP 'WinCustomizer_Toolkit.ps1'
Invoke-WebRequest -Uri $uri -OutFile $file
Get-Content -LiteralPath $file
Get-FileHash -LiteralPath $file -Algorithm SHA256
```

Đọc mã nguồn trước khi chạy. Hash chỉ hữu ích khi so với giá trị nhận qua kênh tin cậy.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file
```

## Lệnh `irm | iex`

`irm` tải nội dung và `iex` thực thi nội dung đó trong phiên PowerShell hiện tại. Nếu phiên đang chạy bằng Administrator, script tải về có quyền Administrator:

```powershell
irm 'https://maclife.vn/wincustomizer' | iex
```

Lệnh CMD tương đương:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://maclife.vn/wincustomizer' | iex"
```

Link rút gọn có thể đổi đích và không xác minh mã nguồn. Chỉ chạy khi tin tưởng và đã kiểm tra owner, repository, đích redirect và nội dung script.

## Tag release

Khi muốn tái lập một phiên bản cố định, tạo tag release sau khi review/push:

```powershell
git tag v2.9.1
git push origin v2.9.1
```

Sau đó dùng Raw URL theo tag thay vì `main`:

```text
https://raw.githubusercontent.com/11h12/win-customizer/v2.9.1/scripts/WinCustomizer_Toolkit.ps1
```

Chỉ dùng tag sau khi tag đó đã được push lên GitHub.
