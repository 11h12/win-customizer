# Windows Customizer Toolkit 2.5.0
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

    $failed = 0
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        }
        catch {
            $failed++
            Write-Warning "Khong xoa duoc '$($_.FullName)': $($_.Exception.Message)"
        }
    }
    if ($failed -gt 0) { throw "$failed item(s) khong xoa duoc trong $Path." }
}

function Invoke-ToolkitTask {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $started = Get-Date
    Write-Host "`n[$Number] [RUNNING] $Name" -ForegroundColor Yellow
    try {
        & $Action
        $elapsed = ((Get-Date) - $started).ToString('hh\:mm\:ss')
        Write-Host "[$Number] [SUCCESS] $Name (thoi gian: $elapsed)" -ForegroundColor Green
        $script:ToolkitTaskResults += [pscustomobject]@{
            Number = $Number
            Name = $Name
            Status = 'SUCCESS'
            Duration = $elapsed
            Error = ''
        }
        return $true
    }
    catch {
        $elapsed = ((Get-Date) - $started).ToString('hh\:mm\:ss')
        $message = $_.Exception.Message
        Write-Host "[$Number] [FAILED] $Name (thoi gian: $elapsed)" -ForegroundColor Red
        Write-Host "      Loi: $message" -ForegroundColor Red
        $script:ToolkitTaskResults += [pscustomobject]@{
            Number = $Number
            Name = $Name
            Status = 'FAILED'
            Duration = $elapsed
            Error = $message
        }
        return $false
    }
}

function Invoke-Step1_CleanAndExport {
    Clear-Host
    Write-Host '=== BUOC 1: DON DEP VA XUAT CAU HINH ===' -ForegroundColor Cyan
    Write-Host 'Moi task chay tuan tu. Trang thai SUCCESS/FAILED va loi se hien ngay sau task.' -ForegroundColor DarkGray
    Write-Host 'Khong xoa Prefetch. Cac tep dang duoc Windows su dung co the khong xoa duoc.' -ForegroundColor DarkGray

    $script:ToolkitTaskResults = @()
    $updateService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wasRunning = $null -ne $updateService -and $updateService.Status -eq 'Running'
    $taskNumber = 0

    try {
        $taskNumber++
        Invoke-ToolkitTask $taskNumber 'Dung Windows Update' {
            if ($null -eq $updateService) { throw 'Khong tim thay dich vu wuauserv.' }
            if ($wasRunning) { Stop-Service -Name wuauserv -Force -ErrorAction Stop }
            else { Write-Host '      Windows Update dang dung san.' -ForegroundColor DarkGray }
        } | Out-Null

        $cleanupTasks = @(
            @{ Name = 'Don temp cua user hien tai'; Path = $env:TEMP },
            @{ Name = 'Don Windows Temp'; Path = (Join-Path $env:WINDIR 'Temp') },
            @{ Name = 'Don cache Windows Update'; Path = (Join-Path $env:WINDIR 'SoftwareDistribution\Download') }
        )
        foreach ($cleanupTask in $cleanupTasks) {
            $taskNumber++
            $path = $cleanupTask.Path
            $name = $cleanupTask.Name
            Invoke-ToolkitTask $taskNumber $name {
                if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                    throw "Khong tim thay thu muc: $path"
                }
                Remove-FolderContents -Path $path
                Write-Host "      Path: $path" -ForegroundColor DarkGray
            } | Out-Null
        }

        $runResetBase = Read-YesNo 'Chay DISM StartComponentCleanup /ResetBase? Update hien co se khong go cai dat duoc'
        $taskNumber++
        if ($runResetBase) {
            Invoke-ToolkitTask $taskNumber 'Chay DISM StartComponentCleanup /ResetBase' {
                & "$env:WINDIR\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup /ResetBase
                if ($LASTEXITCODE -ne 0) { throw "DISM ket thuc voi ma loi $LASTEXITCODE. Kiem tra DISM.log." }
            } | Out-Null
        }
        else {
            Write-Host "[$taskNumber] [SKIPPED] DISM StartComponentCleanup /ResetBase" -ForegroundColor DarkYellow
            $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Chay DISM StartComponentCleanup /ResetBase'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = '' }
        }

        $exportFolder = Join-Path $env:ProgramData 'WinCustomizer\Exports'
        $taskNumber++
        Invoke-ToolkitTask $taskNumber 'Tao thu muc export' {
            New-Item -ItemType Directory -Path $exportFolder -Force -ErrorAction Stop | Out-Null
            Write-Host "      Path: $exportFolder" -ForegroundColor DarkGray
        } | Out-Null

        $associationsPath = Join-Path $exportFolder 'AppAssociations.xml'
        $taskNumber++
        Invoke-ToolkitTask $taskNumber 'Xuat app associations bang DISM' {
            & "$env:WINDIR\System32\dism.exe" /Online "/Export-DefaultAppAssociations:$associationsPath"
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $associationsPath -PathType Leaf)) {
                throw "DISM export that bai (ma $LASTEXITCODE)."
            }
            Write-Host "      File: $associationsPath" -ForegroundColor DarkGray
        } | Out-Null

        $exportStartLayout = Get-Command -Name Export-StartLayout -ErrorAction SilentlyContinue
        $taskNumber++
        if ($null -ne $exportStartLayout) {
            $layoutPath = Join-Path $exportFolder 'StartLayout.json'
            Invoke-ToolkitTask $taskNumber 'Xuat Start layout' {
                Export-StartLayout -Path $layoutPath -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) { throw 'Lenh khong tao ra file StartLayout.json.' }
                Write-Host "      File: $layoutPath" -ForegroundColor DarkGray
            } | Out-Null
        }
        else {
            Write-Host "[$taskNumber] [SKIPPED] Xuat Start layout - khong co Export-StartLayout" -ForegroundColor DarkYellow
            $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Xuat Start layout'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Cmdlet khong co tren ban Windows nay' }
        }
    }
    finally {
        $taskNumber++
        Invoke-ToolkitTask $taskNumber 'Khoi dong lai Windows Update' {
            if ($wasRunning) { Start-Service -Name wuauserv -ErrorAction Stop }
            else { Write-Host '      Giữ nguyen trang thai dang dung.' -ForegroundColor DarkGray }
        } | Out-Null
    }

    Write-Host "`n=== TONG KET BUOC 1 ===" -ForegroundColor Cyan
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
    $failed = @($script:ToolkitTaskResults | Where-Object Status -eq 'FAILED')
    if ($failed.Count -gt 0) {
        Write-Host "BUOC 1 CO $($failed.Count) TASK LOI. Hay sua loi truoc khi sang buoc 2." -ForegroundColor Red
    }
    else {
        Write-Host 'BUOC 1 HOAN TAT; khong co task FAILED.' -ForegroundColor Green
    }
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

    $script:ToolkitTaskResults = @()
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

    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Parse va kiem tra XML' {
        $xmlDocument = [xml]$unattendXml
        if ($xmlDocument.DocumentElement.LocalName -ne 'unattend') { throw 'Root XML khong phai unattend.' }
        $copy = $xmlDocument.SelectSingleNode("//*[local-name()='CopyProfile']")
        if ($null -eq $copy -or $copy.InnerText -ine 'true') { throw 'Thieu CopyProfile=true trong pass specialize.' }
    })){ $passwordEncoded = $null; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Ghi answer file va gioi han quyen doc' {
        [System.IO.File]::WriteAllText($targetPath, $unattendXml, [System.Text.UTF8Encoding]::new($false))
        & "$env:WINDIR\System32\icacls.exe" $targetPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'icacls khong gioi han duoc quyen doc answer file.' }
    })){ $passwordEncoded = $null; return }
    $passwordEncoded = $null; $unattendXml = $null
    Write-Host "Da tao answer file: $targetPath" -ForegroundColor Green
    Write-Host 'Windows SIM voi catalog dung version van la buoc xac minh bat buoc truoc Sysprep.' -ForegroundColor Yellow
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
}

function Test-UnattendForSysprep {
    param([Parameter(Mandatory = $true)][string]$Path)
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($Path)
    $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    $copy = $doc.SelectNodes('/u:unattend/u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:CopyProfile', $ns)
    if ($copy.Count -ne 1 -or $copy[0].InnerText -ine 'true') { throw 'Answer file phai co dung mot CopyProfile=true trong pass specialize.' }
    $account = $doc.SelectSingleNode('/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:UserAccounts/u:LocalAccounts/u:LocalAccount', $ns)
    $accountName = $account.SelectSingleNode('./u:Name', $ns)
    if ($null -eq $account -or $null -eq $accountName -or [string]::IsNullOrWhiteSpace($accountName.InnerText)) { throw 'Khong co LocalAccount hop le trong oobeSystem.' }
    $password = $account.SelectSingleNode('./u:Password/u:Value', $ns)
    if ($null -eq $password -or [string]::IsNullOrWhiteSpace($password.InnerText)) { throw 'LocalAccount khong co password.' }
    try { [void][Convert]::FromBase64String($password.InnerText) } catch { throw 'Password trong answer file khong phai Base64 Unicode hop le.' }
    if ($doc.SelectNodes('//*[local-name()="SkipMachineOOBE" or local-name()="SkipUserOOBE"]').Count -gt 0) { throw 'Khong cho phep SkipMachineOOBE/SkipUserOOBE.' }
    if ($doc.OuterXml -match '(?i)BypassNRO|AutoLogon') { throw 'Khong cho phep BypassNRO hoac AutoLogon trong answer file nay.' }
    return $accountName.InnerText
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

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra answer file Sysprep' { $account = Test-UnattendForSysprep -Path $unattendPath; Write-Host "      Account: $account" -ForegroundColor DarkGray })){ return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra profile truoc khi CopyProfile' {
        $usersPath = Join-Path $env:SystemDrive 'Users'
        $dirs = @(Get-ChildItem -LiteralPath $usersPath -Directory -ErrorAction Stop | Where-Object { $_.Name -notin @('Default','Default User','Public','All Users') })
        if ($dirs.Count -gt 1) { Write-Warning ('Phat hien nhieu profile: ' + (($dirs | Select-Object -ExpandProperty Name) -join ', ') + '. CopyProfile co the lay sai profile.') }
    })){ return }
    Write-Host 'Kiem tra cap nhat, file answer, va ngat ket noi mang truoc khi tiep tuc.' -ForegroundColor Yellow
    Write-Host 'Sysprep /generalize se xoa thong tin may va /shutdown se tat may khi thanh cong.' -ForegroundColor Red
    $confirmation = Read-Host 'Go SYSPREP de xac nhan'
    if ($confirmation -cne 'SYSPREP') {
        Write-Host 'Da huy Sysprep.' -ForegroundColor Yellow
        return
    }

    $taskNumber++; Invoke-ToolkitTask $taskNumber 'Chay Sysprep /generalize /oobe /shutdown' {
        & $sysprepPath /generalize /oobe /shutdown "/unattend:$unattendPath"
        if ($LASTEXITCODE -ne 0) { throw "Sysprep ket thuc voi ma loi $LASTEXITCODE. Kiem tra %WINDIR%\System32\Sysprep\Panther\setupact.log va setuperr.log." }
    } | Out-Null
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
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

    $script:ToolkitTaskResults = @(); $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra file dau vao' {
        foreach ($requiredPath in @($isoSource, $capturedWim)) { if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Khong tim thay file: $requiredPath" } }
        if ([System.IO.Path]::GetExtension($isoSource) -ine '.iso' -or [System.IO.Path]::GetExtension($isoOutput) -ine '.iso') { throw 'ISO dau vao va dau ra phai co phan mo rong .iso.' }
        if ([System.IO.Path]::GetFullPath($isoSource) -ieq [System.IO.Path]::GetFullPath($isoOutput)) { throw 'ISO dau ra phai la file khac ISO goc.' }
        if ((Get-Item -LiteralPath $capturedWim).Length -lt 1MB) { throw 'install.wim qua nho hoac rong.' }
    })){ return }
    $anyBurnCmd = @(
        'C:\Program Files\AnyBurn\abcmd.exe',
        'C:\Program Files (x86)\AnyBurn\abcmd.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $anyBurnCmd) {
        $anyBurnCmd = Read-Host 'Khong tim thay abcmd.exe mac dinh. Nhap duong dan abcmd.exe'
    }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra AnyBurn CLI' { if (-not (Test-Path -LiteralPath $anyBurnCmd -PathType Leaf)) { throw "Khong tim thay AnyBurn CLI: $anyBurnCmd" } })){ return }

    $imageToReplace = $null
    $diskImage = $null
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra install image trong ISO goc' {
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
      } catch { throw "Khong kiem tra duoc ISO goc: $($_.Exception.Message)" }
      finally {
        if ($null -ne $diskImage) {
            Dismount-DiskImage -ImagePath $isoSource -ErrorAction SilentlyContinue | Out-Null
        }
      }
    })){ return }

    if (Test-Path -LiteralPath $isoOutput) {
        if (-not (Read-YesNo "File dau ra da ton tai ($isoOutput). Ghi de?")) {
            Write-Host 'Da huy dong goi ISO.' -ForegroundColor Yellow
            return
        }
    }

    Write-Host "Se thay sources\$imageToReplace bang WIM da capture." -ForegroundColor Yellow
    if (-not (Read-YesNo "Tao ISO tai '$isoOutput'?")) {
        Write-Host 'Da huy dong goi ISO.' -ForegroundColor Yellow
        return
    }
    if (Test-Path -LiteralPath $isoOutput) { Remove-Item -LiteralPath $isoOutput -Force -ErrorAction Stop }

    $arguments = @(
        '-edit', $isoSource,
        '-delete', "\sources\$imageToReplace",
        '-add', $capturedWim, '\sources\',
        '-save', $isoOutput
    )
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'AnyBurn tao ISO' {
        & $anyBurnCmd @arguments
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $isoOutput -PathType Leaf)) { throw "AnyBurn khong tao duoc ISO (ma loi $LASTEXITCODE)." }
    })){ return }
    $taskNumber++; Invoke-ToolkitTask $taskNumber 'Xac minh ISO dau ra co install.wim' {
        if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) { throw 'Khong co Mount-DiskImage tren may nay.' }
        $outDisk = Mount-DiskImage -ImagePath $isoOutput -PassThru -ErrorAction Stop
        try {
            $outVol = $outDisk | Get-Volume -ErrorAction Stop | Where-Object DriveLetter | Select-Object -First 1
            if ($null -eq $outVol -or -not (Test-Path "$($outVol.DriveLetter):\sources\install.wim")) { throw 'ISO dau ra khong co sources\install.wim.' }
        } finally { Dismount-DiskImage -ImagePath $isoOutput -ErrorAction SilentlyContinue | Out-Null }
    } | Out-Null
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize

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
    Write-Host ' WINDOWS CUSTOMIZER AUTOMATION TOOLKIT 2.5.0' -ForegroundColor Yellow
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
