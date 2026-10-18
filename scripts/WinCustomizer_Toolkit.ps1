# Windows Customizer Toolkit 2.4.0
# Requires Windows PowerShell 5.1 and an elevated session.
# Review this script before running it, especially when downloaded from a URL.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    return ((Read-Host "$Prompt [y/N]") -match '^(?i:y|yes)$')
}

function Pause-Toolkit {
    [void](Read-Host 'Nhan Enter de tiep tuc')
}

function Remove-FolderContents {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Khong xoa duoc '$($_.FullName)': $($_.Exception.Message)"
        }
    }
}

function Invoke-Step1_CleanAndExport {
    Clear-Host
    Write-Host '=== BUOC 1: DON DEP VA XUAT CAU HINH ===' -ForegroundColor Cyan
    Write-Host 'Khong xoa Prefetch. Cac tep dang duoc Windows su dung co the khong xoa duoc.' -ForegroundColor DarkGray

    $updateService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wasRunning = $null -ne $updateService -and $updateService.Status -eq 'Running'
    if ($wasRunning) {
        try {
            Stop-Service -Name wuauserv -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Khong dung duoc Windows Update: $($_.Exception.Message)"
        }
    }

    try {
        $cleanupPaths = @(
            $env:TEMP,
            (Join-Path $env:WINDIR 'Temp'),
            (Join-Path $env:WINDIR 'SoftwareDistribution\Download')
        ) | Select-Object -Unique

        foreach ($path in $cleanupPaths) {
            Write-Host "Don dep: $path" -ForegroundColor Yellow
            Remove-FolderContents -Path $path
        }
    }
    finally {
        if ($wasRunning) {
            try {
                Start-Service -Name wuauserv -ErrorAction Stop
            }
            catch {
                Write-Warning "Khong khoi dong lai duoc Windows Update: $($_.Exception.Message)"
            }
        }
    }

    if (Read-YesNo 'Chay DISM StartComponentCleanup /ResetBase? Update hien co se khong go cai dat duoc') {
        & "$env:WINDIR\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup /ResetBase
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "DISM ket thuc voi ma loi $LASTEXITCODE. Kiem tra DISM.log."
        }
        else {
            Write-Host 'DISM component cleanup hoan tat.' -ForegroundColor Green
        }
    }
    else {
        Write-Host 'Da bo qua /ResetBase.' -ForegroundColor Yellow
    }

    $exportFolder = Join-Path $env:ProgramData 'WinCustomizer\Exports'
    New-Item -ItemType Directory -Path $exportFolder -Force | Out-Null
    $associationsPath = Join-Path $exportFolder 'AppAssociations.xml'
    & "$env:WINDIR\System32\dism.exe" /Online "/Export-DefaultAppAssociations:$associationsPath"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Da xuat app associations: $associationsPath" -ForegroundColor Green
    }
    else {
        Write-Warning "DISM export app associations that bai (ma $LASTEXITCODE)."
    }

    $exportStartLayout = Get-Command -Name Export-StartLayout -ErrorAction SilentlyContinue
    if ($null -ne $exportStartLayout) {
        $layoutPath = Join-Path $exportFolder 'StartLayout.json'
        try {
            Export-StartLayout -Path $layoutPath -ErrorAction Stop
            Write-Host "Da xuat Start layout: $layoutPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Khong xuat duoc Start layout: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning 'Khong tim thay Export-StartLayout tren ban Windows nay; bo qua.'
    }

    Write-Host 'Hoan tat buoc 1. Cac file export khong tu dong duoc ap dung vao image.' -ForegroundColor Green
}

function Convert-SecureStringToPlainText {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureString)

    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Read-LocalAdminName {
    while ($true) {
        $name = Read-Host 'Ten tai khoan local admin [mac dinh: Admin]'
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = 'Admin'
        }

        if ($name.Length -le 20 -and $name -notmatch '[\x00-\x1F"/\\\[\]:;|=,+*?<>]') {
            return $name
        }

        Write-Warning 'Ten tai khoan Windows phai dai toi da 20 ky tu va khong chua ky tu cam.'
    }
}

function Read-LocalAdminPassword {
    while ($true) {
        $first = Read-Host 'Mat khau local admin (toi thieu 12 ky tu)' -AsSecureString
        $second = Read-Host 'Nhap lai mat khau' -AsSecureString
        $firstPlain = Convert-SecureStringToPlainText -SecureString $first
        $secondPlain = Convert-SecureStringToPlainText -SecureString $second

        if ($firstPlain.Length -ge 12 -and $firstPlain -ceq $secondPlain) {
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($firstPlain))
            $first.Dispose()
            $second.Dispose()
            $firstPlain = $null
            $secondPlain = $null
            return $encoded
        }

        $first.Dispose()
        $second.Dispose()
        $firstPlain = $null
        $secondPlain = $null
        Write-Warning 'Mat khau khong khop hoac it hon 12 ky tu. Hay thu lai.'
    }
}

function Invoke-Step2_GenerateUnattendXml {
    Clear-Host
    Write-Host '=== BUOC 2: TAO UNATTEND.XML ===' -ForegroundColor Cyan
    Write-Warning 'Answer file chua thong tin tai khoan. Base64 khong phai ma hoa; khong commit hoac chia se file.'

    $adminUser = Read-LocalAdminName
    $passwordEncoded = Read-LocalAdminPassword
    $preserveDrivers = Read-YesNo 'Image chi dung cho cung model/cau hinh phan cung? Neu khong chac, chon No'
    $driverSettings = ''
    if ($preserveDrivers) {
        $driverSettings = @'
  <settings pass="generalize">
    <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <PersistAllDeviceInstalls>true</PersistAllDeviceInstalls>
    </component>
  </settings>
'@
    }
    $escapedAdminUser = [System.Security.SecurityElement]::Escape($adminUser)
    $targetPath = Join-Path $env:WINDIR 'System32\Sysprep\unattend.xml'

    if (Test-Path -LiteralPath $targetPath) {
        if (-not (Read-YesNo "File da ton tai ($targetPath). Ghi de file cu?")) {
            Write-Host 'Da huy, file cu duoc giu nguyen.' -ForegroundColor Yellow
            return
        }
    }

    $unattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
$driverSettings
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <CopyProfile>true</CopyProfile>
      <TimeZone>SE Asia Standard Time</TimeZone>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$escapedAdminUser</Name>
            <DisplayName>$escapedAdminUser</DisplayName>
            <Group>Administrators</Group>
            <Password>
              <Value>$passwordEncoded</Value>
              <PlainText>false</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
    </component>
  </settings>
</unattend>
"@

    try {
        $xmlDocument = [xml]$unattendXml
        [System.IO.File]::WriteAllText($targetPath, $unattendXml, [System.Text.UTF8Encoding]::new($false))
        & "$env:WINDIR\System32\icacls.exe" $targetPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
            throw 'icacls khong the gioi han quyen doc answer file; file vua tao da bi xoa.'
        }
    }
    catch {
        throw "Khong tao duoc answer file: $($_.Exception.Message)"
    }
    finally {
        $passwordEncoded = $null
        $unattendXml = $null
        $xmlDocument = $null
    }

    Write-Host "Da tao answer file: $targetPath" -ForegroundColor Green
    Write-Host 'Hay validate bang Windows SIM voi catalog cua dung ban Windows truoc khi Sysprep.' -ForegroundColor Yellow
}

function Invoke-Step3_RunSysprep {
    Clear-Host
    Write-Host '=== BUOC 3: SYSPREP VA TAT MAY ===' -ForegroundColor Cyan
    $unattendPath = Join-Path $env:WINDIR 'System32\Sysprep\unattend.xml'
    $sysprepPath = Join-Path $env:WINDIR 'System32\Sysprep\Sysprep.exe'

    if (-not (Test-Path -LiteralPath $unattendPath -PathType Leaf)) {
        Write-Error "Khong tim thay $unattendPath. Hay tao answer file truoc."
        return
    }
    if (-not (Test-Path -LiteralPath $sysprepPath -PathType Leaf)) {
        Write-Error "Khong tim thay $sysprepPath."
        return
    }

    Write-Host 'Kiem tra cap nhat, file answer, va ngat ket noi mang truoc khi tiep tuc.' -ForegroundColor Yellow
    Write-Host 'Sysprep generalize se chuan bi lai Windows va may se tat khi thanh cong.' -ForegroundColor Red
    $confirmation = Read-Host 'Go SYSPREP de xac nhan'
    if ($confirmation -cne 'SYSPREP') {
        Write-Host 'Da huy Sysprep.' -ForegroundColor Yellow
        return
    }

    & $sysprepPath /generalize /oobe /shutdown "/unattend:$unattendPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Sysprep ket thuc voi ma loi $LASTEXITCODE. Kiem tra Panther logs truoc khi thu lai."
    }
}

function Invoke-Step4_BuildISO {
    Clear-Host
    Write-Host '=== BUOC 4: THAY WIM VA DONG GOI ISO ===' -ForegroundColor Cyan

    $isoSource = Read-Host 'Duong dan ISO Windows goc'
    $capturedWim = Read-Host 'Duong dan file install.wim da capture'
    $isoOutput = Read-Host 'Duong dan ISO dau ra [Windows_Custom.iso]'
    if ([string]::IsNullOrWhiteSpace($isoOutput)) {
        $isoOutput = Join-Path (Get-Location).Path 'Windows_Custom.iso'
    }

    foreach ($requiredPath in @($isoSource, $capturedWim)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Write-Error "Khong tim thay file: $requiredPath"
            return
        }
    }
    if ([System.IO.Path]::GetExtension($isoSource) -ine '.iso' -or [System.IO.Path]::GetExtension($isoOutput) -ine '.iso') {
        Write-Error 'ISO dau vao va dau ra phai co phan mo rong .iso.'
        return
    }
    if ([System.IO.Path]::GetFullPath($isoSource) -ieq [System.IO.Path]::GetFullPath($isoOutput)) {
        Write-Error 'ISO dau ra phai la file khac ISO goc.'
        return
    }

    $anyBurnCmd = @(
        'C:\Program Files\AnyBurn\abcmd.exe',
        'C:\Program Files (x86)\AnyBurn\abcmd.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $anyBurnCmd) {
        $anyBurnCmd = Read-Host 'Khong tim thay abcmd.exe mac dinh. Nhap duong dan abcmd.exe'
    }
    if (-not (Test-Path -LiteralPath $anyBurnCmd -PathType Leaf)) {
        Write-Error "Khong tim thay AnyBurn CLI: $anyBurnCmd"
        return
    }

    $imageToReplace = $null
    $diskImage = $null
    try {
        $diskImage = Mount-DiskImage -ImagePath $isoSource -PassThru -ErrorAction Stop
        $volume = $diskImage | Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter } | Select-Object -First 1
        if ($null -eq $volume) {
            throw 'Khong tim thay drive letter cua ISO sau khi mount.'
        }
        $sourcesPath = "$($volume.DriveLetter):\sources"
        if (Test-Path -LiteralPath (Join-Path $sourcesPath 'install.wim')) {
            $imageToReplace = 'install.wim'
        }
        elseif (Test-Path -LiteralPath (Join-Path $sourcesPath 'install.esd')) {
            $imageToReplace = 'install.esd'
        }
        elseif (Get-ChildItem -LiteralPath $sourcesPath -Filter 'install*.swm' -ErrorAction SilentlyContinue) {
            throw 'ISO dung install*.swm chia phan; toolkit chua ho tro thay bo SWM.'
        }
        else {
            throw 'Khong tim thay sources\install.wim hoac install.esd trong ISO goc.'
        }
    }
    catch {
        Write-Error "Khong kiem tra duoc ISO goc: $($_.Exception.Message)"
        return
    }
    finally {
        if ($null -ne $diskImage) {
            Dismount-DiskImage -ImagePath $isoSource -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (Test-Path -LiteralPath $isoOutput) {
        if (-not (Read-YesNo "File dau ra da ton tai ($isoOutput). Ghi de?")) {
            Write-Host 'Da huy dong goi ISO.' -ForegroundColor Yellow
            return
        }
        Remove-Item -LiteralPath $isoOutput -Force -ErrorAction Stop
    }

    Write-Host "Se thay sources\$imageToReplace bang WIM da capture." -ForegroundColor Yellow
    if (-not (Read-YesNo "Tao ISO tai '$isoOutput'?")) {
        Write-Host 'Da huy dong goi ISO.' -ForegroundColor Yellow
        return
    }

    $arguments = @(
        '-edit', $isoSource,
        '-delete', "\sources\$imageToReplace",
        '-add', $capturedWim, '\sources\',
        '-save', $isoOutput
    )
    & $anyBurnCmd @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $isoOutput -PathType Leaf)) {
        Write-Error "AnyBurn khong tao duoc ISO (ma loi $LASTEXITCODE). Kiem tra tham so theo ban AnyBurn CLI cua ban."
        return
    }

    Write-Host "Da tao ISO: $isoOutput" -ForegroundColor Green
    Write-Host 'Hay mount ISO, kiem tra WIM va boot thu trong VM truoc khi phat hanh.' -ForegroundColor Yellow
}

if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
    Write-Error 'Toolkit can Windows PowerShell 5.1 tro len.'
    return
}
if (-not (Test-IsAdministrator)) {
    Write-Error 'Hay mo Windows PowerShell bang quyen Administrator.'
    return
}

$continueMenu = $true
while ($continueMenu) {
    Clear-Host
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host ' WINDOWS CUSTOMIZER AUTOMATION TOOLKIT 2.4.0' -ForegroundColor Yellow
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host ' 1. Don dep va xuat app associations/Start layout'
    Write-Host ' 2. Tao Sysprep unattend.xml'
    Write-Host ' 3. Chay Sysprep /generalize /oobe /shutdown'
    Write-Host ' 4. Thay install.wim trong ISO bang AnyBurn CLI'
    Write-Host ' Q. Thoat toolkit'
    Write-Host '=================================================' -ForegroundColor Cyan

    switch ((Read-Host 'Chon buoc (1-4 hoac Q)').ToUpperInvariant()) {
        '1' { Invoke-Step1_CleanAndExport; Pause-Toolkit }
        '2' { Invoke-Step2_GenerateUnattendXml; Pause-Toolkit }
        '3' { Invoke-Step3_RunSysprep; Pause-Toolkit }
        '4' { Invoke-Step4_BuildISO; Pause-Toolkit }
        'Q' { $continueMenu = $false }
        default { Write-Host 'Lua chon khong hop le.' -ForegroundColor Red; Start-Sleep -Seconds 2 }
    }
}
