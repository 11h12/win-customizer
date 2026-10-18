# Windows Customizer Toolkit 2.9.1
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
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [switch]$DefaultYes
    )
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return [bool]$DefaultYes }
    return ($answer -match '^(?i:y|yes)$')
}

function Read-OptionalValue {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [AllowEmptyString()][string]$Default = ''
    )

    $suffix = if ([string]::IsNullOrWhiteSpace($Default)) { '' } else { " [$Default]" }
    $value = Read-Host "$Prompt$suffix (NONE = bo setting nay)"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    if ($value.Trim() -ieq 'NONE') { return '' }
    return $value.Trim()
}

function ConvertTo-XmlText {
    param([AllowEmptyString()][string]$Value)
    return [System.Security.SecurityElement]::Escape($Value)
}

function Read-LocalAccountName {
    while ($true) {
        $name = (Read-Host 'Ten local account tao trong OOBE').Trim()
        if (Test-LocalAccountName -Name $name) {
            return $name
        }
        Write-Warning 'Ten local account phai co 1-20 ky tu, khong phai NONE, va khong chua ky tu Windows cam.'
    }
}

function Read-LocalAccountPasswordBase64 {
    while ($true) {
        $first = Read-Host 'Mat khau local account (khong ap dat toi thieu 12 ky tu)' -AsSecureString
        $second = Read-Host 'Nhap lai mat khau' -AsSecureString
        $firstPointer = [IntPtr]::Zero
        $secondPointer = [IntPtr]::Zero
        $firstPlain = $null
        $secondPlain = $null
        try {
            $firstPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
            $secondPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
            $firstPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($firstPointer)
            $secondPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secondPointer)
            if ($firstPlain.Length -gt 0 -and $firstPlain -ceq $secondPlain) {
                return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($firstPlain))
            }
        }
        finally {
            if ($firstPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($firstPointer) }
            if ($secondPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secondPointer) }
            $first.Dispose()
            $second.Dispose()
            $firstPlain = $null
            $secondPlain = $null
        }
        Write-Warning 'Mat khau dang rong hoac khong khop. Hay thu lai.'
    }
}

function Read-LocaleValue {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [AllowEmptyString()][string]$Default = '',
        [switch]$Required
    )

    while ($true) {
        $suffix = if ([string]::IsNullOrWhiteSpace($Default)) { '' } else { " [$Default]" }
        $emptyHint = if ($Required) { '(khong bo trong)' } else { '(NONE = bo setting nay)' }
        $value = (Read-Host "$Prompt$suffix $emptyHint").Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        if ($value -ieq 'NONE' -or [string]::IsNullOrWhiteSpace($value)) {
            if ($Required) { Write-Warning "$Prompt bat buoc de answer file cau hinh OOBE day du."; continue }
            return ''
        }
        if (Test-LocaleName -Value $value) { return $value }
        else {
            Write-Warning "Locale '$value' khong hop le. Dung ma dang vi-VN, en-US."
        }
    }
}

function Test-LocaleName {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z]{2,3}(?:-[A-Za-z]{4})?-(?:[A-Za-z]{2}|[0-9]{3})$') { return $false }
    try {
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($Value)
        return (-not $culture.IsNeutralCulture)
    }
    catch { return $false }
}

function Get-InstalledUiLanguageTags {
    $languageKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages'
    try {
        return @(Get-ChildItem -LiteralPath $languageKey -ErrorAction Stop | Select-Object -ExpandProperty PSChildName)
    }
    catch {
        return @()
    }
}

function Read-InstalledUiLanguageValue {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [AllowEmptyString()][string]$Default = '',
        [Parameter(Mandatory = $true)][string[]]$InstalledLanguages,
        [switch]$Required
    )

    while ($true) {
        if ($InstalledLanguages.Count -eq 0) {
            Write-Warning 'Khong doc duoc danh sach UI language da cai. Khong tao answer file khi chua xac minh UILanguage tren may nay.'
            return $null
        }
        $value = Read-LocaleValue -Prompt $Prompt -Default $Default -Required:$Required
        if ([string]::IsNullOrWhiteSpace($value)) { return '' }
        if ($InstalledLanguages -contains $value) { return $value }
        Write-Warning "UI language '$value' khong nam trong danh sach language pack dang cai: $($InstalledLanguages -join ', ')."
    }
}

function Test-LocalAccountName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 20 -or $Name -ieq 'NONE') { return $false }
    return ($Name -notmatch '[\x00-\x1F"/\\\[\]:|<>+=;,?*%@`]')
}

function Test-InputLocaleValue {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $knownKeyboardLayouts = @()
    try { $knownKeyboardLayouts = @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts' -ErrorAction Stop | Select-Object -ExpandProperty PSChildName) }
    catch { }
    foreach ($part in $Value.Split(';')) {
        $entry = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($entry)) { return $false }
        if ($entry -match '^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{8})$') {
            try {
                $keyboardCulture = [System.Globalization.CultureInfo]::GetCultureInfo([Convert]::ToInt32($Matches[1], 16))
                if ($keyboardCulture.IsNeutralCulture) { return $false }
            }
            catch { return $false }
            if ($knownKeyboardLayouts.Count -gt 0 -and $knownKeyboardLayouts -notcontains $Matches[2]) { return $false }
            continue
        }
        if (-not (Test-LocaleName -Value $entry)) { return $false }
    }
    return $true
}

function Test-AnswerFileArchitecture {
    param([Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Document)

    $components = $Document.SelectNodes('//*[local-name()="component"]')
    if ($components.Count -eq 0) { throw 'Answer file khong co component.' }
    $architecture = $null
    foreach ($component in $components) {
        $componentArchitecture = $component.GetAttribute('processorArchitecture')
        if ($componentArchitecture -notin @('amd64', 'x86')) { throw "processorArchitecture khong hop le tren component '$($component.GetAttribute('name'))'." }
        if ($null -eq $architecture) { $architecture = $componentArchitecture }
        elseif ($architecture -ne $componentArchitecture) { throw 'Answer file dang tron component amd64 va x86.' }
        if ($component.GetAttribute('publicKeyToken') -ne '31bf3856ad364e35' -or $component.GetAttribute('language') -ne 'neutral' -or $component.GetAttribute('versionScope') -ne 'nonSxS') {
            throw "Component identity khong dung tren '$($component.GetAttribute('name'))'."
        }
    }
}

function Get-CurrentWindowsAnswerFileArchitecture {
    $nativeArchitecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($nativeArchitecture)) { $nativeArchitecture = $env:PROCESSOR_ARCHITECTURE }
    if ([string]::IsNullOrWhiteSpace($nativeArchitecture)) { throw 'Khong doc duoc architecture cua Windows dang chay.' }
    switch ($nativeArchitecture.ToUpperInvariant()) {
        'AMD64' { return 'amd64' }
        'X86' { return 'x86' }
        default { throw "Windows architecture '$nativeArchitecture' chua duoc toolkit ho tro cho Sysprep answer file." }
    }
}

function Test-AnswerFileNamespaces {
    param([Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Document)

    $foreignElements = $Document.SelectNodes('//*[namespace-uri() != "urn:schemas-microsoft-com:unattend"]')
    foreach ($element in $foreignElements) {
        $isWindowsSimMetadata = $element.NamespaceURI -eq 'urn:schemas-microsoft-com:cpi' -and $element.LocalName -eq 'offlineImage' -and $element.ParentNode -eq $Document.DocumentElement
        if (-not $isWindowsSimMetadata) { throw "XML element ngoai namespace khong duoc ho tro: {$($element.NamespaceURI)}$($element.LocalName)." }
    }
}

function Test-UnattendForSysprep {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'Document')][System.Xml.XmlDocument]$Document
    )
    if ($PSCmdlet.ParameterSetName -eq 'Document') { $doc = $Document }
    else {
        $doc = New-Object System.Xml.XmlDocument
        $doc.PreserveWhitespace = $true
        $doc.Load($Path)
    }
    if ($doc.DocumentElement.LocalName -ne 'unattend' -or $doc.DocumentElement.NamespaceURI -ne 'urn:schemas-microsoft-com:unattend') {
        throw 'Root/namespace XML khong phai Windows Unattend.'
    }
    Test-AnswerFileNamespaces -Document $doc
    Test-AnswerFileArchitecture -Document $doc
    $expectedArchitecture = Get-CurrentWindowsAnswerFileArchitecture
    $actualArchitecture = $doc.SelectSingleNode('//*[local-name()="component"]').GetAttribute('processorArchitecture')
    if ($actualArchitecture -ne $expectedArchitecture) { throw "Architecture answer file ($actualArchitecture) khac Windows dang chay ($expectedArchitecture)." }
    foreach ($child in $doc.DocumentElement.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
        if ($child.NamespaceURI -eq 'urn:schemas-microsoft-com:unattend' -and $child.LocalName -ne 'settings') { throw "Root setting '$($child.LocalName)' khong duoc ho tro trong file Sysprep nay." }
    }

    $allowedByPass = @{
        generalize = @{ 'Microsoft-Windows-PnpSysprep' = @('PersistAllDeviceInstalls') }
        specialize = @{ 'Microsoft-Windows-Shell-Setup' = @('CopyProfile', 'TimeZone') }
        oobeSystem = @{
            'Microsoft-Windows-International-Core' = @('InputLocale', 'SystemLocale', 'UILanguage', 'UILanguageFallback', 'UserLocale')
            'Microsoft-Windows-Shell-Setup' = @('OOBE', 'UserAccounts')
        }
    }
    $settings = $doc.SelectNodes('/*[local-name()="unattend"]/*[local-name()="settings"]')
    if ($settings.Count -eq 0) { throw 'Answer file Sysprep khong co configuration pass nao.' }
    $oobePasses = @($settings | Where-Object { $_.GetAttribute('pass') -eq 'oobeSystem' })
    if ($oobePasses.Count -ne 1) { throw 'Answer file Sysprep phai co dung mot pass oobeSystem de cau hinh OOBE.' }
    $internationalComponents = $oobePasses[0].SelectNodes('./*[local-name()="component" and @name="Microsoft-Windows-International-Core"]')
    if ($internationalComponents.Count -ne 1) { throw 'oobeSystem phai co dung mot Microsoft-Windows-International-Core.' }
    foreach ($requiredLocale in @('InputLocale', 'SystemLocale', 'UILanguage', 'UserLocale')) {
        $requiredNodes = $internationalComponents[0].SelectNodes("./*[local-name()='$requiredLocale']")
        if ($requiredNodes.Count -ne 1) {
            throw "oobeSystem\Microsoft-Windows-International-Core\$requiredLocale bat buoc co dung mot gia tri de cau hinh ngon ngu/vung/ban phim OOBE."
        }
        if ([string]::IsNullOrWhiteSpace($requiredNodes[0].InnerText)) {
            throw "oobeSystem\Microsoft-Windows-International-Core\$requiredLocale bat buoc co dung mot gia tri de cau hinh ngon ngu/vung/ban phim OOBE."
        }
    }
    $seenPasses = @{}
    foreach ($passNode in $settings) {
        $pass = $passNode.GetAttribute('pass')
        if (-not $allowedByPass.ContainsKey($pass)) { throw "Configuration pass khong duoc ho tro: '$pass'." }
        if ($seenPasses.ContainsKey($pass)) { throw "Pass '$pass' bi lap; hay gop setting vao mot pass duy nhat." }
        $seenPasses[$pass] = $true
        $components = $passNode.SelectNodes('./*[local-name()="component"]')
        if ($components.Count -eq 0) { throw "Pass '$pass' khong co component." }
        $seenComponents = @{}
        foreach ($component in $components) {
            $componentName = $component.GetAttribute('name')
            if (-not $allowedByPass[$pass].ContainsKey($componentName)) { throw "Component '$componentName' khong dung/khong duoc ho tro trong pass '$pass'." }
            if ($seenComponents.ContainsKey($componentName)) { throw "Component '$componentName' bi lap trong pass '$pass'." }
            $seenComponents[$componentName] = $true
            $allowedChildren = @($allowedByPass[$pass][$componentName])
            foreach ($child in $component.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
                if ($allowedChildren -notcontains $child.LocalName) { throw "Setting '$($child.LocalName)' khong hop le cho component '$componentName' trong pass '$pass'." }
            }
        }
    }

    if ($doc.SelectNodes('//*[local-name()="HideLocalAccountScreen"]').Count -gt 0) { throw 'HideLocalAccountScreen chi ap dung cho Windows Server, khong dua vao Windows client.' }
    if ($doc.SelectNodes('//*[local-name()="HideWirelessSetupInOOBE" or local-name()="WiFiProfile" or local-name()="WLANProfile"]').Count -gt 0) { throw 'Answer file co setting Wi-Fi; toolkit duoc cau hinh de khong tao setting nay.' }
    if ($doc.SelectNodes('//*[local-name()="SkipMachineOOBE" or local-name()="SkipUserOOBE" or local-name()="AutoLogon" or local-name()="BypassNRO"]').Count -gt 0) { throw 'Answer file chua setting bi cam trong quy trinh nay: SkipMachineOOBE/SkipUserOOBE/AutoLogon/BypassNRO.' }

    foreach ($nodeName in @('CopyProfile', 'TimeZone', 'PersistAllDeviceInstalls', 'InputLocale', 'SystemLocale', 'UILanguage', 'UILanguageFallback', 'UserLocale', 'OOBE', 'UserAccounts')) {
        if ($doc.SelectNodes("//*[local-name()='$nodeName']").Count -gt 1) { throw "Setting '$nodeName' bi lap." }
    }
    $copy = $doc.SelectSingleNode('//*[local-name()="CopyProfile"]')
    if ($null -ne $copy -and $copy.InnerText -ine 'true') { throw 'CopyProfile neu co phai co mot gia tri true.' }
    $persist = $doc.SelectSingleNode('//*[local-name()="PersistAllDeviceInstalls"]')
    if ($null -ne $persist -and $persist.InnerText -notin @('true', 'false')) { throw 'PersistAllDeviceInstalls chi nhan true/false.' }
    foreach ($boolName in @('HideEULAPage', 'HideOnlineAccountScreens', 'HideOEMRegistrationScreen')) {
        $nodes = $doc.SelectNodes("//*[local-name()='$boolName']")
        foreach ($node in $nodes) { if ($node.InnerText -notin @('true', 'false')) { throw "$boolName chi nhan true/false." } }
    }
    $protectYourPc = $doc.SelectSingleNode('//*[local-name()="ProtectYourPC"]')
    if ($null -ne $protectYourPc -and $protectYourPc.InnerText -notin @('1', '2', '3')) { throw 'ProtectYourPC chi nhan 1, 2 hoac 3.' }

    $oobeNode = $doc.SelectSingleNode('//*[local-name()="OOBE"]')
    if ($null -eq $oobeNode) { throw 'oobeSystem\Microsoft-Windows-Shell-Setup phai co mot OOBE section do wizard tao.' }
    if ($null -ne $oobeNode) {
        $allowedOobe = @('HideEULAPage', 'HideOnlineAccountScreens', 'HideOEMRegistrationScreen', 'ProtectYourPC')
        $seenOobeSettings = @{}
        foreach ($child in $oobeNode.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($allowedOobe -notcontains $child.LocalName) { throw "OOBE setting '$($child.LocalName)' khong duoc ho tro." }
            if ($seenOobeSettings.ContainsKey($child.LocalName)) { throw "OOBE setting '$($child.LocalName)' bi lap." }
            $seenOobeSettings[$child.LocalName] = $true
        }
    }

    foreach ($localeName in @('InputLocale', 'SystemLocale', 'UILanguage', 'UILanguageFallback', 'UserLocale')) {
        $localeNodes = $doc.SelectNodes("//*[local-name()='$localeName']")
        foreach ($localeNode in $localeNodes) {
            if ($localeName -eq 'InputLocale') {
                if (-not (Test-InputLocaleValue -Value $localeNode.InnerText)) { throw "InputLocale khong hop le: '$($localeNode.InnerText)'." }
            }
            else {
                if (-not (Test-LocaleName -Value $localeNode.InnerText)) { throw "Locale '$localeName' khong hop le: '$($localeNode.InnerText)'." }
            }
            if ($localeName -in @('UILanguage', 'UILanguageFallback')) {
                $installedLanguages = @(Get-InstalledUiLanguageTags)
                if ($installedLanguages.Count -eq 0 -or $installedLanguages -notcontains $localeNode.InnerText) { throw "$localeName '$($localeNode.InnerText)' khong duoc xac nhan la language pack dang cai tren image tham chieu." }
            }
        }
    }
    $timeZoneNode = $doc.SelectSingleNode('//*[local-name()="TimeZone"]')
    if ($null -ne $timeZoneNode) {
        $timeZoneIds = @()
        try { $timeZoneIds = @(Get-TimeZone -ListAvailable | Select-Object -ExpandProperty Id) }
        catch { throw 'Khong the doc danh sach timezone de kiem tra answer file.' }
        if ($timeZoneIds.Count -eq 0 -or $timeZoneIds -notcontains $timeZoneNode.InnerText) { throw "TimeZone khong ton tai tren Windows nay: '$($timeZoneNode.InnerText)'." }
    }

    $localAccounts = $doc.SelectNodes('//*[local-name()="LocalAccount"]')
    if ($localAccounts.Count -gt 1) { throw 'Toolkit chi tao mot LocalAccount trong answer file.' }
    $userAccountsNodes = $doc.SelectNodes('//*[local-name()="UserAccounts"]')
    if ($userAccountsNodes.Count -gt 1) { throw 'Toolkit chi ho tro mot UserAccounts.' }
    if ($userAccountsNodes.Count -eq 1) {
        $userAccounts = $userAccountsNodes[0]
        foreach ($child in $userAccounts.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -ne 'LocalAccounts') { throw "UserAccounts setting '$($child.LocalName)' khong duoc ho tro trong toolkit nay." }
        }
        $localAccountsContainers = $userAccounts.SelectNodes('./*[local-name()="LocalAccounts"]')
        if ($localAccountsContainers.Count -ne 1) { throw 'UserAccounts can co dung mot LocalAccounts.' }
        foreach ($child in $localAccountsContainers[0].ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -ne 'LocalAccount') { throw "LocalAccounts setting '$($child.LocalName)' khong duoc ho tro." }
        }
        if ($localAccounts.Count -ne 1) { throw 'Toolkit chi ho tro dung mot LocalAccount neu UserAccounts duoc khai bao.' }
        if ($localAccountsContainers[0].SelectNodes('./*[local-name()="LocalAccount"]').Count -ne 1) { throw 'LocalAccounts phai co dung mot LocalAccount.' }
    }
    foreach ($account in $localAccounts) {
        foreach ($child in $account.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -notin @('Name', 'Group', 'DisplayName', 'Password')) { throw "LocalAccount setting '$($child.LocalName)' khong duoc ho tro." }
        }
        foreach ($childName in @('Name', 'Group', 'Password')) {
            if ($account.SelectNodes("./*[local-name()='$childName']").Count -ne 1) { throw "LocalAccount can co dung mot setting '$childName'." }
        }
        $name = $account.SelectSingleNode('./*[local-name()="Name"]')
        $group = $account.SelectSingleNode('./*[local-name()="Group"]')
        $passwordValue = $account.SelectSingleNode('./*[local-name()="Password"]/*[local-name()="Value"]')
        $plainText = $account.SelectSingleNode('./*[local-name()="Password"]/*[local-name()="PlainText"]')
        $passwordNode = $account.SelectSingleNode('./*[local-name()="Password"]')
        if ($account.SelectNodes('./*[local-name()="DisplayName"]').Count -gt 1 -or $account.SelectNodes('./*[local-name()="Password"]').Count -ne 1) { throw 'LocalAccount chi duoc co toi da mot DisplayName va dung mot Password.' }
        foreach ($child in $passwordNode.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -notin @('Value', 'PlainText')) { throw "Password setting '$($child.LocalName)' khong duoc ho tro." }
        }
        if ($passwordNode.SelectNodes('./*[local-name()="Value"]').Count -ne 1 -or $passwordNode.SelectNodes('./*[local-name()="PlainText"]').Count -ne 1) { throw 'LocalAccount Password can dung mot Value va mot PlainText.' }
        if ($account.GetAttribute('action', 'http://schemas.microsoft.com/WMIConfig/2002/State') -ne 'add') { throw 'LocalAccount can co wcm:action="add".' }
        if ($null -eq $name -or -not (Test-LocalAccountName -Name $name.InnerText)) { throw 'LocalAccount Name rong, bi cam hoac khong hop le.' }
        if ($null -eq $group -or $group.InnerText -ne 'Administrators') { throw 'LocalAccount do toolkit tao phai nam trong Administrators de tranh OOBE bo qua tao account va khong con tai khoan quan tri.' }
        if ($null -eq $passwordValue -or $null -eq $plainText -or $plainText.InnerText -ine 'false') { throw 'LocalAccount Password can Value Base64 va PlainText=false.' }
        try { $passwordBytes = [Convert]::FromBase64String($passwordValue.InnerText) }
        catch { throw 'LocalAccount Password Value khong phai Base64 hop le.' }
        try {
            if ($passwordBytes.Length -eq 0 -or ($passwordBytes.Length % 2) -ne 0) { throw 'LocalAccount Password Value khong phai chuoi UTF-16LE hop le.' }
        }
        finally { [Array]::Clear($passwordBytes, 0, $passwordBytes.Length) }
    }

    $accountSummary = if ($localAccounts.Count -gt 0) { "[OOBE se tao $($localAccounts.Count) local account tu answer file]" } else { '[OOBE se yeu cau tao/dang nhap account thu cong]' }
    return $accountSummary
}

function Test-AutounattendForSetup {
    param([Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Document)

    if ($Document.DocumentElement.LocalName -ne 'unattend' -or $Document.DocumentElement.NamespaceURI -ne 'urn:schemas-microsoft-com:unattend') { throw 'Root/namespace XML khong phai Windows Unattend.' }
    Test-AnswerFileNamespaces -Document $Document
    Test-AnswerFileArchitecture -Document $Document
    foreach ($child in $Document.DocumentElement.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
        if ($child.NamespaceURI -eq 'urn:schemas-microsoft-com:unattend' -and $child.LocalName -ne 'settings') { throw "Root setting '$($child.LocalName)' khong duoc ho tro trong autounattend.xml nay." }
    }
    $passes = $Document.SelectNodes('/*[local-name()="unattend"]/*[local-name()="settings"]')
    if ($passes.Count -lt 1 -or $passes.Count -gt 2) { throw 'autounattend.xml phai co windowsPE va toi da mot pass oobeSystem.' }
    $seenPasses = @{}
    foreach ($pass in $passes) {
        $passName = $pass.GetAttribute('pass')
        if ($passName -notin @('windowsPE', 'oobeSystem')) { throw "Pass '$passName' khong duoc ho tro trong autounattend.xml nay." }
        if ($seenPasses.ContainsKey($passName)) { throw "Pass '$passName' bi lap trong autounattend.xml." }
        $seenPasses[$passName] = $true
    }
    if (-not $seenPasses.ContainsKey('windowsPE')) { throw 'autounattend.xml bat buoc co pass windowsPE.' }
    $windowsPePass = @($passes | Where-Object { $_.GetAttribute('pass') -eq 'windowsPE' })[0]
    $components = $windowsPePass.SelectNodes('./*[local-name()="component"]')
    if ($components.Count -ne 1 -or $components[0].GetAttribute('name') -ne 'Microsoft-Windows-Setup') { throw 'windowsPE phai co dung component Microsoft-Windows-Setup.' }
    foreach ($child in $components[0].ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
        if ($child.LocalName -ne 'UserData') { throw "Setting '$($child.LocalName)' khong duoc ho tro trong autounattend.xml nay." }
    }
    $userDataNodes = $components[0].SelectNodes('./*[local-name()="UserData"]')
    if ($userDataNodes.Count -ne 1) { throw 'windowsPE phai co dung mot UserData.' }
    $userData = $userDataNodes[0]
    if ($userData.SelectNodes('./*[local-name()="AcceptEula"]').Count -ne 1) { throw 'UserData phai co dung mot AcceptEula.' }
    foreach ($child in $userData.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
        if ($child.LocalName -notin @('AcceptEula', 'ProductKey')) { throw "UserData setting '$($child.LocalName)' khong duoc ho tro." }
    }
    $eula = $userData.SelectSingleNode('./*[local-name()="AcceptEula"]')
    if ($null -eq $eula -or $eula.InnerText -ine 'true') { throw 'UserData/AcceptEula phai la true cho file Setup nay.' }
    $productKeys = $userData.SelectNodes('./*[local-name()="ProductKey"]')
    if ($productKeys.Count -gt 1) { throw 'UserData chi duoc co mot ProductKey.' }
    if ($userData.SelectNodes('./*[local-name()="AcceptEula"]').Count -ne 1) { throw 'UserData/AcceptEula bi lap.' }
    foreach ($keyNode in $productKeys) {
        foreach ($child in $keyNode.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -notin @('Key', 'WillShowUI')) { throw "ProductKey setting '$($child.LocalName)' khong hop le." }
        }
        $key = $keyNode.SelectSingleNode('./*[local-name()="Key"]')
        $willShowUi = $keyNode.SelectSingleNode('./*[local-name()="WillShowUI"]')
        if ($keyNode.SelectNodes('./*[local-name()="Key"]').Count -ne 1 -or $keyNode.SelectNodes('./*[local-name()="WillShowUI"]').Count -gt 1) { throw 'ProductKey can dung mot Key va toi da mot WillShowUI.' }
        if ($null -eq $key -or $key.InnerText -notmatch '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') { throw 'ProductKey/Key phai dung dinh dang 25 ky tu.' }
        if ($null -ne $willShowUi -and $willShowUi.InnerText -notin @('Always', 'OnError', 'Never')) { throw 'ProductKey/WillShowUI khong hop le.' }
    }

    $oobePasses = @($passes | Where-Object { $_.GetAttribute('pass') -eq 'oobeSystem' })
    if ($oobePasses.Count -eq 1) {
        $oobeComponents = $oobePasses[0].SelectNodes('./*[local-name()="component"]')
        if ($oobeComponents.Count -ne 1 -or $oobeComponents[0].GetAttribute('name') -ne 'Microsoft-Windows-Shell-Setup') { throw 'oobeSystem chi ho tro mot component Microsoft-Windows-Shell-Setup cho ProtectYourPC.' }
        foreach ($child in $oobeComponents[0].ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -ne 'OOBE') { throw "oobeSystem setting '$($child.LocalName)' khong duoc ho tro trong autounattend.xml nay." }
        }
        $oobeNodes = $oobeComponents[0].SelectNodes('./*[local-name()="OOBE"]')
        if ($oobeNodes.Count -ne 1) { throw 'oobeSystem\Microsoft-Windows-Shell-Setup phai co dung mot OOBE section.' }
        foreach ($child in $oobeNodes[0].ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)) {
            if ($child.LocalName -ne 'ProtectYourPC') { throw "OOBE setting '$($child.LocalName)' khong duoc ho tro trong autounattend.xml nay." }
        }
        $protectYourPcNodes = $oobeNodes[0].SelectNodes('./*[local-name()="ProtectYourPC"]')
        if ($protectYourPcNodes.Count -ne 1 -or $protectYourPcNodes[0].InnerText -notin @('1', '2', '3')) { throw 'OOBE\ProtectYourPC phai co dung mot gia tri 1, 2 hoac 3.' }
    }
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

function Invoke-ManualToolkitTask {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Instructions
    )

    Invoke-ToolkitTask $Number $Name {
        foreach ($instruction in $Instructions) { Write-Host "      $instruction" -ForegroundColor Yellow }
        $confirmation = Read-Host 'Chi nhap DONE sau khi hoan tat dung task nay'
        if ($confirmation -cne 'DONE') { throw 'Nguoi dung chua xac nhan task thu cong hoan tat.' }
    } | Out-Null
}

function Invoke-DismWithProgress {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    $lastPercent = -1
    & "$env:WINDIR\System32\dism.exe" @Arguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        if ($line -match '(\d{1,3}(?:[\.,]\d+)?)%') {
            $percentText = $Matches[1].Replace(',', '.')
            $percent = [int][math]::Min(100, [math]::Max(0, [math]::Round([double]$percentText)))
            if ($percent -ne $lastPercent) {
                Write-Progress -Activity $Activity -Status "$percent%" -PercentComplete $percent
                $lastPercent = $percent
            }
        }
        Write-Host "      $line"
    }
    $exitCode = $LASTEXITCODE
    Write-Progress -Activity $Activity -Completed
    return $exitCode
}

function Publish-StagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$StagedPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $StagedPath -PathType Leaf)) { throw "Khong tim thay file staging: $StagedPath" }
    if ((Test-Path -LiteralPath $DestinationPath) -and -not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { throw "Duong dan dich da ton tai nhung khong phai file: $DestinationPath" }
    $backupPath = $null
    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
        $destinationDirectory = Split-Path -Parent $DestinationPath
        $destinationStem = [System.IO.Path]::GetFileNameWithoutExtension($DestinationPath)
        $destinationExtension = [System.IO.Path]::GetExtension($DestinationPath)
        $backupPath = Join-Path $destinationDirectory "$destinationStem.previous.$([guid]::NewGuid().ToString('N'))$destinationExtension"
        Move-Item -LiteralPath $DestinationPath -Destination $backupPath -ErrorAction Stop
    }

    try {
        Move-Item -LiteralPath $StagedPath -Destination $DestinationPath -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { throw "Khong thay file tai dich sau khi publish: $DestinationPath" }
    }
    catch {
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf) -and -not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
            try { Move-Item -LiteralPath $backupPath -Destination $DestinationPath -ErrorAction Stop }
            catch { throw "Publish that bai va khong khoi phuc duoc file cu. Ban cu con tai '$backupPath'. Loi rollback: $($_.Exception.Message)" }
        }
        throw
    }

    if ($null -ne $backupPath) { Write-Host "      Ban cu duoc giu tai: $backupPath" -ForegroundColor Yellow }
}

function Set-RestrictedAnswerFileAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Khong tim thay answer file can bao ve: $Path" }
    $icaclsPath = Join-Path $env:WINDIR 'System32\icacls.exe'
    & $icaclsPath $Path /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'icacls khong the gioi han quyen doc answer file.' }

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $acl.AreAccessRulesProtected) { throw 'ACL answer file van ke thua quyen tu thu muc cha.' }
    $allowedSids = @('S-1-5-18', 'S-1-5-32-544')
    $rules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
    $ruleSids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Select-Object -Unique)
    if (@($ruleSids | Where-Object { $_ -notin $allowedSids }).Count -gt 0 -or @($allowedSids | Where-Object { $_ -notin $ruleSids }).Count -gt 0) {
        throw 'DACL answer file khong chi gioi han cho SYSTEM va local Administrators.'
    }
}

function Copy-FileWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$StagedPath,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Khong tim thay file nguon: $SourcePath" }
    if (Test-Path -LiteralPath $StagedPath) { throw "File staging da ton tai: $StagedPath" }
    $sourceStream = $null
    $destinationStream = $null
    try {
        $sourceStream = [System.IO.File]::Open($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $destinationStream = [System.IO.File]::Open($StagedPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] (4MB)
        $total = $sourceStream.Length
        $copied = [int64]0
        while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $destinationStream.Write($buffer, 0, $read)
            $copied += $read
            $percent = if ($total -gt 0) { [int][math]::Min(100, [math]::Floor(($copied * 100) / $total)) } else { 100 }
            Write-Progress -Activity $Activity -Status "$percent% ($([math]::Round($copied / 1MB, 0)) / $([math]::Round($total / 1MB, 0)) MB)" -PercentComplete $percent
        }
        $destinationStream.Flush()
    }
    finally {
        if ($null -ne $destinationStream) { $destinationStream.Dispose() }
        if ($null -ne $sourceStream) { $sourceStream.Dispose() }
        Write-Progress -Activity $Activity -Completed
    }
    if (-not (Test-Path -LiteralPath $StagedPath -PathType Leaf) -or (Get-Item -LiteralPath $StagedPath).Length -ne (Get-Item -LiteralPath $SourcePath).Length) {
        throw "Kiem tra kich thuoc sau copy that bai; file staging duoc giu tai $StagedPath"
    }
}

function Invoke-Step1_ExportUserSettings {
    Clear-Host
    Write-Host '=== BUOC 1: EXPORT DEFAULT APPS/START LAYOUT TRUOC KHI VAO AUDIT ===' -ForegroundColor Cyan
    Write-Host 'Chay khi da hoan tat OOBE va dang dang nhap bang user tam da tuy chinh default apps/Start.' -ForegroundColor Yellow
    Write-Host 'Export o day truoc khi xoa profile tam; neu export tu Audit Administrator se lay setting cua tai khoan do.' -ForegroundColor DarkGray

    $defaultExportFolder = Join-Path $env:ProgramData 'WinCustomizer\Exports'
    try {
        $backupVolume = Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq 'BACKUP' -and $_.DriveLetter } | Select-Object -First 1
        if ($null -ne $backupVolume) { $defaultExportFolder = Join-Path ("$($backupVolume.DriveLetter):\") 'WinCustomizer\Exports' }
    }
    catch { }
    $exportFolder = (Read-Host "Thu muc luu export (nen chon o BACKUP de map/copy tren host) [$defaultExportFolder]").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($exportFolder)) { $exportFolder = $defaultExportFolder }
    $exportFolder = [System.IO.Path]::GetFullPath($exportFolder)
    $associationsPath = Join-Path $exportFolder 'AppAssociations.xml'
    $isWindows11 = [Environment]::OSVersion.Version.Build -ge 22000
    $layoutName = if ($isWindows11) { 'StartLayout.json' } else { 'LayoutModification.xml' }
    $layoutPath = Join-Path $exportFolder $layoutName
    $exportId = [guid]::NewGuid().ToString('N')
    $associationsStage = Join-Path $exportFolder ".AppAssociations.export-$exportId.xml"
    $layoutStage = Join-Path $exportFolder ".$layoutName.export-$exportId"

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan da vao Windows bang user da hoan tat OOBE' {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($currentSid -match '-500$') { throw 'Hay export khi dang dang nhap bang user tam da cau hinh default apps/Start, truoc khi xoa profile va vao Audit.' }
        Write-Host '      Dang chay user OOBE tam; co the export app associations cua user nay.' -ForegroundColor DarkGray
    })) { Write-PostCaptureTaskSummary; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao thu muc export tren BACKUP/host' {
        if (-not (Test-Path -LiteralPath $exportFolder -PathType Container)) { New-Item -ItemType Directory -Path $exportFolder -Force -ErrorAction Stop | Out-Null }
        Write-Host "      Thu muc: $exportFolder" -ForegroundColor DarkGray
    })) { Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan co the thay file export cu sau khi ban moi da tao thanh cong' {
        $existingExports = @($associationsPath, $layoutPath) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        if ($existingExports.Count -gt 0) {
            Write-Host ('      File cu se duoc giu thanh ban .previous neu export moi thanh cong: ' + ($existingExports -join ', ')) -ForegroundColor Yellow
            if (-not (Read-YesNo 'Tiep tuc va publish cac file export moi?')) { throw 'Nguoi dung huy; file export cu duoc giu nguyen.' }
        }
    })) { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    $associationsExported = Invoke-ToolkitTask $taskNumber 'DISM Export-DefaultAppAssociations vao staging' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Online "/Export-DefaultAppAssociations:$associationsStage"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $associationsStage -PathType Leaf)) { throw "DISM export that bai (ma $LASTEXITCODE)." }
        Write-Host "      Staging: $associationsStage" -ForegroundColor DarkGray
    }

    $exportStartLayout = Get-Command -Name Export-StartLayout -ErrorAction SilentlyContinue
    $taskNumber++
    $layoutExported = $false
    if ($null -ne $exportStartLayout) {
        $layoutExported = Invoke-ToolkitTask $taskNumber "Export Start layout thanh $layoutName vao staging" {
            Export-StartLayout -Path $layoutStage -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $layoutStage -PathType Leaf)) { throw "Export-StartLayout khong tao ra $layoutName." }
            Write-Host "      Staging: $layoutStage" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "[$taskNumber] [SKIPPED] Export Start layout - khong co Export-StartLayout" -ForegroundColor DarkYellow
        $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Export Start layout'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Cmdlet khong co tren ban Windows nay' }
    }
    $taskNumber++
    if ($associationsExported) {
        Invoke-ToolkitTask $taskNumber 'Publish AppAssociations.xml sau khi DISM export thanh cong' {
            Publish-StagedFile -StagedPath $associationsStage -DestinationPath $associationsPath
            Write-Host "      File: $associationsPath" -ForegroundColor DarkGray
        } | Out-Null
    }
    else {
        Write-Host "[$taskNumber] [SKIPPED] Publish AppAssociations.xml - DISM export that bai" -ForegroundColor DarkYellow
        $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Publish AppAssociations.xml'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'DISM export that bai; file cu duoc giu nguyen' }
    }

    $taskNumber++
    if ($layoutExported) {
        Invoke-ToolkitTask $taskNumber 'Publish Start layout sau khi export thanh cong' {
            Publish-StagedFile -StagedPath $layoutStage -DestinationPath $layoutPath
            Write-Host "      File: $layoutPath" -ForegroundColor DarkGray
        } | Out-Null
    }
    elseif ($null -ne $exportStartLayout) {
        Write-Host "[$taskNumber] [SKIPPED] Publish Start layout - export that bai" -ForegroundColor DarkYellow
        $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Publish Start layout'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Export that bai; file cu duoc giu nguyen' }
    }
    else {
        Write-Host "[$taskNumber] [SKIPPED] Publish Start layout - cmdlet khong co tren Windows nay" -ForegroundColor DarkYellow
        $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Publish Start layout'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Khong co file layout moi' }
    }
    Write-PostCaptureTaskSummary
    Write-Host 'Ghi lai duong dan export de dung o menu Post-capture sau khi capture xong.' -ForegroundColor Yellow
}

function Invoke-Step2_CleanInAudit {
    Clear-Host
    Write-Host '=== BUOC 2: CLEANUP TRONG AUDIT MODE ===' -ForegroundColor Cyan
    Write-Host 'Moi task chay tuan tu. Trang thai SUCCESS/FAILED va loi se hien ngay sau task.' -ForegroundColor DarkGray
    Write-Host 'Khong xoa Prefetch. Cac tep dang duoc Windows su dung co the khong xoa duoc.' -ForegroundColor DarkGray

    $script:ToolkitTaskResults = @()
    $updateService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wasRunning = $null -ne $updateService -and $updateService.Status -eq 'Running'
    $taskNumber = 0

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan dang o Audit Mode bang built-in Administrator' {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($currentSid -notmatch '-500$') { throw 'Hoan tat OOBE bang user tam, sau do vao Audit Mode bang Sysprep GUI va dang nhap built-in Administrator truoc khi cleanup.' }
        Write-Host '      Dang chay built-in Administrator (SID-RID 500).' -ForegroundColor DarkGray
    })) { return }

    $updateStopped = $false
    $cleanupTasksSucceeded = $true
    try {
        $taskNumber++
        $updateStopped = Invoke-ToolkitTask $taskNumber 'Dung Windows Update' {
            if ($null -eq $updateService) { throw 'Khong tim thay dich vu wuauserv.' }
            if ($wasRunning) {
                Stop-Service -Name wuauserv -Force -ErrorAction Stop
                (Get-Service -Name wuauserv -ErrorAction Stop).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
            }
            else { Write-Host '      Windows Update dang dung san.' -ForegroundColor DarkGray }
        }
        if (-not $updateStopped) { $cleanupTasksSucceeded = $false }

        $cleanupTasks = @(
            @{ Name = 'Don temp cua user hien tai'; Path = $env:TEMP },
            @{ Name = 'Don Windows Temp'; Path = (Join-Path $env:WINDIR 'Temp') }
        )
        foreach ($cleanupTask in $cleanupTasks) {
            $taskNumber++
            $path = $cleanupTask.Path
            $name = $cleanupTask.Name
            if (-not (Invoke-ToolkitTask $taskNumber $name {
                if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                    throw "Khong tim thay thu muc: $path"
                }
                Remove-FolderContents -Path $path
                Write-Host "      Path: $path" -ForegroundColor DarkGray
            })) { $cleanupTasksSucceeded = $false }
        }

        $taskNumber++
        if ($updateStopped) {
            if (-not (Invoke-ToolkitTask $taskNumber 'Don cache Windows Update' {
                $path = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
                if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Khong tim thay thu muc: $path" }
                Remove-FolderContents -Path $path
                Write-Host "      Path: $path" -ForegroundColor DarkGray
            })) { $cleanupTasksSucceeded = $false }
        }
        else {
            Write-Host "[$taskNumber] [SKIPPED] Don cache Windows Update - khong dung duoc dich vu" -ForegroundColor DarkYellow
            $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Don cache Windows Update'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Can dung Windows Update truoc khi xoa cache' }
        }

        $runResetBase = Read-YesNo 'Chay DISM StartComponentCleanup /ResetBase? Update hien co se khong go cai dat duoc'
        $taskNumber++
        if ($runResetBase) {
            if ($cleanupTasksSucceeded) {
                Invoke-ToolkitTask $taskNumber 'Chay DISM StartComponentCleanup /ResetBase' {
                    $dismCode = Invoke-DismWithProgress -Activity 'DISM Component Cleanup /ResetBase' -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')
                    if ($dismCode -ne 0) { throw "DISM ket thuc voi ma loi $dismCode. Kiem tra DISM.log." }
                } | Out-Null
            }
            else {
                Write-Host "[$taskNumber] [SKIPPED] DISM StartComponentCleanup /ResetBase - task don truoc do co loi" -ForegroundColor DarkYellow
                $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Chay DISM StartComponentCleanup /ResetBase'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Task cleanup truoc do co loi' }
            }
        }
        else {
            Write-Host "[$taskNumber] [SKIPPED] DISM StartComponentCleanup /ResetBase" -ForegroundColor DarkYellow
            $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Chay DISM StartComponentCleanup /ResetBase'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = '' }
        }

        $taskNumber++
        Invoke-ToolkitTask $taskNumber 'Phan tich Component Store sau cleanup' {
            $dismCode = Invoke-DismWithProgress -Activity 'DISM AnalyzeComponentStore' -Arguments @('/Online', '/Cleanup-Image', '/AnalyzeComponentStore')
            if ($dismCode -ne 0) { throw "DISM AnalyzeComponentStore ket thuc voi ma loi $dismCode. Kiem tra DISM.log." }
        } | Out-Null

        if (Read-YesNo 'Mo thu muc Start Menu dung chung cho moi user?') {
            $taskNumber++
            Invoke-ToolkitTask $taskNumber 'Mo thu muc Start Menu dung chung' {
                $sharedStartMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
                New-Item -ItemType Directory -Path $sharedStartMenu -Force -ErrorAction Stop | Out-Null
                Start-Process explorer.exe -ArgumentList "`"$sharedStartMenu`""
                Write-Host "      $sharedStartMenu" -ForegroundColor DarkGray
            } | Out-Null
        }
    }
    finally {
        $taskNumber++
        Invoke-ToolkitTask $taskNumber 'Khoi dong lai Windows Update' {
            if ($wasRunning) {
                Start-Service -Name wuauserv -ErrorAction Stop
                (Get-Service -Name wuauserv -ErrorAction Stop).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
            }
            else { Write-Host '      Giữ nguyen trang thai dang dung.' -ForegroundColor DarkGray }
        } | Out-Null
    }

    Write-Host "`n=== TONG KET BUOC 2 ===" -ForegroundColor Cyan
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
    $failed = @($script:ToolkitTaskResults | Where-Object Status -eq 'FAILED')
    $skipped = @($script:ToolkitTaskResults | Where-Object Status -eq 'SKIPPED')
    if ($failed.Count -gt 0) {
        Write-Host "BUOC 2 CO $($failed.Count) TASK LOI. Hay sua loi truoc khi sang buoc 3." -ForegroundColor Red
    }
    elseif ($skipped.Count -gt 0) {
        Write-Host "BUOC 2 KHONG CO TASK FAILED; co $($skipped.Count) task SKIPPED. Xem ly do truoc khi sang buoc 3." -ForegroundColor Yellow
    }
    else {
        Write-Host 'BUOC 2 HOAN TAT; tat ca task da chay thanh cong.' -ForegroundColor Green
    }
}

function Invoke-Step3_GenerateUnattendXml {
    Clear-Host
    Write-Host '=== BUOC 3: TAO UNATTEND.XML ===' -ForegroundColor Cyan
    Write-Host 'Wizard hoi locale, quoc gia/vung, ban phim, mui gio, OOBE va tuy chon tao local account.' -ForegroundColor DarkGray
    Write-Host 'Gia tri mac dinh la setting cua Windows hien tai. UILanguage/SystemLocale/UserLocale/InputLocale bat buoc de cau hinh locale va keyboard OOBE; TimeZone/Fallback co the bo. Khong co setting Wi-Fi.' -ForegroundColor DarkGray

    $targetPath = Join-Path $env:WINDIR 'System32\Sysprep\unattend.xml'
    if (Test-Path -LiteralPath $targetPath) {
        if (-not (Read-YesNo "File da ton tai ($targetPath). Ghi de file cu?")) {
            Write-Host 'Da huy, file cu duoc giu nguyen.' -ForegroundColor Yellow
            return
        }
    }

    $script:ToolkitTaskResults = @()
    $copyProfile = Read-YesNo 'Da tuy chinh profile built-in Administrator trong Audit va chi con profile do? Chi khi dung moi bat CopyProfile'
    $preserveDrivers = Read-YesNo 'Image chi dung cho cung model/cau hinh phan cung? Neu khong chac, chon No'
    $architecture = Get-CurrentWindowsAnswerFileArchitecture
    Write-Host "Kien truc answer file Sysprep duoc lay tu Windows dang chay: $architecture" -ForegroundColor DarkGray

    $createLocalAccount = Read-YesNo 'Tao local account trong unattend (OOBE se tu tao account nay)?'
    $localAccountName = ''
    $localAccountPassword = ''
    $localAccountGroup = 'Administrators'
    if ($createLocalAccount) {
        $localAccountName = Read-LocalAccountName
        $localAccountPassword = Read-LocalAccountPasswordBase64
        Write-Host 'Account tao boi answer file se vao Administrators. Sau OOBE, tao them standard user rieng neu can.' -ForegroundColor Yellow
    }

    $installedUiLanguages = @(Get-InstalledUiLanguageTags)
    $defaultUiLanguage = $PSUICulture.Name
    if ($installedUiLanguages -notcontains $defaultUiLanguage) { $defaultUiLanguage = $installedUiLanguages | Select-Object -First 1 }
    if ([string]::IsNullOrWhiteSpace($defaultUiLanguage)) { $defaultUiLanguage = (Get-Culture).Name }

    $defaultSystemLocale = ''
    try { $defaultSystemLocale = (Get-WinSystemLocale).Name } catch { $defaultSystemLocale = (Get-Culture).Name }
    $defaultUserLocale = (Get-Culture).Name
    $defaultInputLocale = ''
    try {
        $defaultInputLocale = @((Get-WinUserLanguageList | ForEach-Object { $_.InputMethodTips } | Where-Object { $_ } | Select-Object -Unique) -join ';')
    }
    catch { }
    if ([string]::IsNullOrWhiteSpace($defaultInputLocale)) { $defaultInputLocale = '0409:00000409' }
    $defaultTimeZone = ''
    try { $defaultTimeZone = (Get-TimeZone).Id } catch { }

    if ($installedUiLanguages.Count -gt 0) { Write-Host "UI language da cai tren may: $($installedUiLanguages -join ', ')" -ForegroundColor DarkGray }
    $uiLanguage = Read-InstalledUiLanguageValue -Prompt 'Ngon ngu giao dien Windows (UILanguage; phai co language pack trong image)' -Default $defaultUiLanguage -InstalledLanguages $installedUiLanguages -Required
    if ($null -eq $uiLanguage) { return }
    $systemLocale = Read-LocaleValue -Prompt 'Locale he thong cho chuong trinh non-Unicode (SystemLocale)' -Default $defaultSystemLocale -Required
    $userLocale = Read-LocaleValue -Prompt 'Quoc gia/vung va dinh dang ngay/gio (UserLocale; vi-VN = Viet Nam, en-US = Hoa Ky)' -Default $defaultUserLocale -Required
    while ($true) {
        $inputPrompt = 'Ban phim/bo go (InputLocale; co the nhap vi-VN hoac 0409:00000409;042A:0000042A)'
        $inputSuffix = if ([string]::IsNullOrWhiteSpace($defaultInputLocale)) { '' } else { " [$defaultInputLocale]" }
        $inputLocale = (Read-Host "$inputPrompt$inputSuffix (bat buoc de cau hinh keyboard OOBE)").Trim()
        if ([string]::IsNullOrWhiteSpace($inputLocale)) { $inputLocale = $defaultInputLocale }
        if (-not [string]::IsNullOrWhiteSpace($inputLocale) -and $inputLocale -ine 'NONE' -and (Test-InputLocaleValue -Value $inputLocale)) { break }
        Write-Warning 'InputLocale bat buoc va phai hop le; layout ma hex can ton tai tren Windows dang dung.'
    }
    $uiLanguageFallback = Read-InstalledUiLanguageValue -Prompt 'UILanguageFallback (chi can cho UI language chi duoc dich mot phan; NONE neu khong can)' -Default '' -InstalledLanguages $installedUiLanguages
    if ($null -eq $uiLanguageFallback) { return }

    $timeZone = Read-OptionalValue -Prompt 'Mui gio Windows (TimeZone; xem danh sach bang tzutil /l)' -Default $defaultTimeZone
    if (-not [string]::IsNullOrWhiteSpace($timeZone)) {
        $availableTimeZones = @()
        try { $availableTimeZones = @(Get-TimeZone -ListAvailable | Select-Object -ExpandProperty Id) } catch { }
        if ($availableTimeZones.Count -gt 0 -and $timeZone -notin $availableTimeZones) {
            Write-Warning "Khong tim thay timezone '$timeZone' tren may nay. Kiem tra ten chinh xac bang tzutil /l."
            return
        }
    }

    Write-Host 'Microsoft gioi han HideEULAPage cho OEM/System Builder testing truoc khi xuat ban.' -ForegroundColor Yellow
    $hideEulaPage = Read-YesNo 'An trang EULA (HideEULAPage)? Chi chon Yes neu dung trong pham vi duoc phep.'
    $hideOnlineAccountScreens = Read-YesNo 'An trang dang nhap Microsoft account? (khong tao local user neu chua chon UserAccounts)' -DefaultYes:$createLocalAccount
    $hideOemRegistrationScreen = Read-YesNo 'An trang dang ky OEM (HideOEMRegistrationScreen)?'
    $protectYourPc = (Read-Host 'ProtectYourPC: 3=tat Express Settings (khuyen nghi), 1/2=bat, NONE=de OOBE hoi [3]').Trim()
    if ([string]::IsNullOrWhiteSpace($protectYourPc)) { $protectYourPc = '3' }
    while ($protectYourPc -notin @('1', '2', '3', 'NONE', 'none')) {
        Write-Warning 'ProtectYourPC chi chap nhan 1, 2, 3 hoac NONE.'
        $protectYourPc = (Read-Host 'ProtectYourPC (1/2/3/NONE)').Trim()
    }
    if ($protectYourPc -ieq 'NONE') { $protectYourPc = '' }

    $backupPath = Read-Host 'Thu muc backup tuy chon (Enter de bo qua)'
    if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
        $backupPath = $backupPath.Trim().Trim('"')
        if ($backupPath -notmatch '^[A-Za-z]:\\') {
            $backupPath = Join-Path -Path (Get-Location).Path -ChildPath $backupPath
        }
    }
    $specializeElements = @()
    if ($copyProfile) { $specializeElements += '      <CopyProfile>true</CopyProfile>' }
    if (-not [string]::IsNullOrWhiteSpace($timeZone)) { $specializeElements += "      <TimeZone>$(ConvertTo-XmlText $timeZone)</TimeZone>" }
    $specializeXml = ''
    if ($specializeElements.Count -gt 0) {
        $specializeXml = @"
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
$($specializeElements -join "`r`n")
    </component>
  </settings>
"@
    }

    $internationalElements = @()
    foreach ($setting in @(
        @{ Name = 'InputLocale'; Value = $inputLocale },
        @{ Name = 'SystemLocale'; Value = $systemLocale },
        @{ Name = 'UILanguage'; Value = $uiLanguage },
        @{ Name = 'UILanguageFallback'; Value = $uiLanguageFallback },
        @{ Name = 'UserLocale'; Value = $userLocale }
    )) {
        if (-not [string]::IsNullOrWhiteSpace($setting.Value)) {
            $internationalElements += "      <$($setting.Name)>$(ConvertTo-XmlText $setting.Value)</$($setting.Name)>"
        }
    }
    $internationalXml = ''
    if ($internationalElements.Count -gt 0) {
        $internationalXml = @"
    <component name="Microsoft-Windows-International-Core" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
$($internationalElements -join "`r`n")
    </component>
"@
    }

    $driverSettings = ''
    if ($preserveDrivers) {
        $driverSettings = @"
  <settings pass="generalize">
    <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <PersistAllDeviceInstalls>true</PersistAllDeviceInstalls>
    </component>
  </settings>
"@
    }
    $oobeElements = @(
        "        <HideEULAPage>$($hideEulaPage.ToString().ToLowerInvariant())</HideEULAPage>",
        "        <HideOnlineAccountScreens>$($hideOnlineAccountScreens.ToString().ToLowerInvariant())</HideOnlineAccountScreens>",
        "        <HideOEMRegistrationScreen>$($hideOemRegistrationScreen.ToString().ToLowerInvariant())</HideOEMRegistrationScreen>"
    )
    if (-not [string]::IsNullOrWhiteSpace($protectYourPc)) {
        $oobeElements += "        <ProtectYourPC>$protectYourPc</ProtectYourPC>"
    }

    $localAccountXml = ''
    if ($createLocalAccount) {
        $escapedAccountName = ConvertTo-XmlText $localAccountName
        $localAccountXml = @"
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Password>
              <Value>$localAccountPassword</Value>
              <PlainText>false</PlainText>
            </Password>
            <DisplayName>$escapedAccountName</DisplayName>
            <Group>$localAccountGroup</Group>
            <Name>$escapedAccountName</Name>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
"@
    }

    $unattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
$driverSettings
$specializeXml
  <settings pass="oobeSystem">
$internationalXml
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
$($oobeElements -join "`r`n")
      </OOBE>
$localAccountXml
    </component>
  </settings>
</unattend>
"@

    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Parse XML va xac minh component/pass/setting' {
        $xmlDocument = [xml]$unattendXml
        $account = Test-UnattendForSysprep -Document $xmlDocument
        Write-Host "      $account" -ForegroundColor DarkGray
    })){ return }
    $stagePath = Join-Path (Split-Path -Parent $targetPath) ".unattend.stage-$([guid]::NewGuid().ToString('N')).xml"
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao staging va khoa ACL truoc khi ghi answer file' {
        $stream = [System.IO.File]::Open($stagePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Dispose()
        Set-RestrictedAnswerFileAcl -Path $stagePath
    })){ Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Ghi staging va doc lai XML tu dia' {
        [System.IO.File]::WriteAllText($stagePath, $unattendXml, [System.Text.UTF8Encoding]::new($false))
        [void](Test-UnattendForSysprep -Path $stagePath)
    })){ Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Publish answer file, giu file cu neu co' {
        Publish-StagedFile -StagedPath $stagePath -DestinationPath $targetPath
        [void](Test-UnattendForSysprep -Path $targetPath)
        Set-RestrictedAnswerFileAcl -Path $targetPath
    })){ Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue; return }
    $unattendXml = $null
    $localAccountPassword = $null
    if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
        $backupStage = $null
        try {
            $backupPath = [System.IO.Path]::GetFullPath($backupPath)
            $backupRoot = [System.IO.Path]::GetPathRoot($backupPath)
            $isRoot = -not [string]::IsNullOrWhiteSpace($backupRoot) -and $backupPath.TrimEnd('\') -ieq $backupRoot.TrimEnd('\')
            if ($isRoot -and -not (Test-Path -LiteralPath $backupPath -PathType Container)) {
                throw "Khong tim thay o luu backup: $backupPath"
            }
            if (-not $isRoot -and -not (Test-Path -LiteralPath $backupPath -PathType Container)) {
                New-Item -ItemType Directory -Path $backupPath -Force -ErrorAction Stop | Out-Null
            }
            $backupFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($backupPath, 'unattend.xml'))
            if ($backupFile -ieq [System.IO.Path]::GetFullPath($targetPath)) {
                throw 'Thu muc backup trung voi thu muc Sysprep; khong the backup vao chinh file dang su dung.'
            }
            $backupStage = [System.IO.Path]::Combine($backupPath, ".unattend.backup-stage-$([guid]::NewGuid().ToString('N')).xml")
            $stageStream = [System.IO.File]::Open($backupStage, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stageStream.Dispose()
            Set-RestrictedAnswerFileAcl -Path $backupStage
            $sourceStream = $null
            $stageStream = $null
            try {
                $sourceStream = [System.IO.File]::OpenRead($targetPath)
                $stageStream = [System.IO.File]::Open($backupStage, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $sourceStream.CopyTo($stageStream)
                $stageStream.Flush($true)
            }
            finally {
                if ($null -ne $stageStream) { $stageStream.Dispose() }
                if ($null -ne $sourceStream) { $sourceStream.Dispose() }
            }
            Set-RestrictedAnswerFileAcl -Path $backupStage
            [void](Test-UnattendForSysprep -Path $backupStage)
            if ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $backupStage -Algorithm SHA256).Hash) {
                throw 'SHA-256 answer file backup staging khong khop file dang su dung.'
            }
            Publish-StagedFile -StagedPath $backupStage -DestinationPath $backupFile
            $backupStage = $null
            Set-RestrictedAnswerFileAcl -Path $backupFile
            if ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash) {
                throw 'SHA-256 answer file backup sau publish khong khop file dang su dung.'
            }
            Write-Host "Da backup answer file: $backupFile" -ForegroundColor Yellow
        }
        catch {
            if ($backupStage -and (Test-Path -LiteralPath $backupStage -PathType Leaf)) { Remove-Item -LiteralPath $backupStage -Force -ErrorAction SilentlyContinue }
            Write-Warning "Khong backup duoc answer file vao '$backupPath': $($_.Exception.Message)"
        }
    }
    Write-Host "Da tao answer file: $targetPath" -ForegroundColor Green
    if ($createLocalAccount) {
        Write-Host 'Answer file co username va password local account da encode Base64; Day khong phai ma hoa bao mat. Bao ve/xoa file sau deploy.' -ForegroundColor Red
    }
    Write-Host 'Windows SIM voi catalog dung version van la buoc xac minh bat buoc truoc Sysprep.' -ForegroundColor Yellow
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
}

function Invoke-Step4_RunSysprep {
    Clear-Host
    Write-Host '=== BUOC 4: SYSPREP VA TAT MAY ===' -ForegroundColor Cyan
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
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan dang chay trong Audit Mode bang built-in Administrator' {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($currentSid -notmatch '-500$') { throw 'Khong phai built-in Administrator (SID-RID 500). Hoan tat OOBE bang user tam, sau do vao Audit Mode bang Sysprep GUI; khong chay final Sysprep tu tai khoan OOBE.' }
        Write-Host '      Dang chay bang built-in Administrator; SID ket thuc -500.' -ForegroundColor DarkGray
    })){ return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra answer file Sysprep' { $account = Test-UnattendForSysprep -Path $unattendPath; Write-Host "      Account: $account" -ForegroundColor DarkGray })){ return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra profile truoc khi CopyProfile' {
        $profileAnswer = New-Object System.Xml.XmlDocument
        $profileAnswer.Load($unattendPath)
        $docCopyProfile = $profileAnswer.SelectSingleNode('//*[local-name()="CopyProfile"]')
        $copyProfile = $null -ne $docCopyProfile -and $docCopyProfile.InnerText -ieq 'true'
        if (-not $copyProfile) { Write-Host '      CopyProfile khong bat; bo qua kiem tra so luong profile.' -ForegroundColor DarkGray; return }
        $usersPath = (Join-Path $env:SystemDrive 'Users').TrimEnd('\') + '\'
        $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object {
            $_.LocalPath -and $_.LocalPath.StartsWith($usersPath, [StringComparison]::OrdinalIgnoreCase) -and -not $_.Special
        })
        $adminProfile = @($profiles | Where-Object { $_.SID -match '-500$' })
        $otherProfiles = @($profiles | Where-Object { $_.SID -notmatch '-500$' })
        if ($adminProfile.Count -ne 1) { throw 'Khong xac dinh duoc duy nhat profile cua built-in Administrator (SID-RID 500); khong chay Sysprep voi CopyProfile.' }
        if (-not (Test-Path -LiteralPath $adminProfile[0].LocalPath -PathType Container)) { throw "Profile built-in Administrator khong ton tai: $($adminProfile[0].LocalPath)" }
        if ($otherProfiles.Count -gt 0) { throw ('CopyProfile dang bat nhung van con user profile khac; xoa profile tam truoc khi Sysprep: ' + (($otherProfiles | Select-Object -ExpandProperty LocalPath) -join ', ')) }
        Write-Host "      Profile duy nhat se copy: $($adminProfile[0].LocalPath)" -ForegroundColor DarkGray
    })){ return }
    Write-Host 'Quy trinh nay bat dau sau khi da hoan tat OOBE tao user tam, cap nhat/cai app, roi chuyen vao Audit Mode bang Sysprep GUI.' -ForegroundColor Yellow
    Write-Host 'Kiem tra cap nhat, answer file da xac minh bang Windows SIM, va ngat ket noi mang truoc khi tiep tuc.' -ForegroundColor Yellow
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

function Invoke-Step5_CaptureWim {
    Clear-Host
    Write-Host '=== BUOC 5: CAPTURE WIM TRONG WINPE ===' -ForegroundColor Cyan
    Write-Warning 'Chi chay sau khi Sysprep /shutdown da tat may. Khong capture khi Windows tham chieu dang chay.'
    $script:ToolkitTaskResults = @()
    $taskNumber = 0

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Hien thi volume va kiem tra cong cu' {
        if (-not (Test-Path -LiteralPath "$env:WINDIR\System32\dism.exe" -PathType Leaf)) { throw 'Khong tim thay DISM trong moi truong hien tai.' }
        if (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
            Get-Volume | Where-Object DriveLetter | Sort-Object DriveLetter | Format-Table DriveLetter, FileSystemLabel, FileSystem, SizeRemaining, Size -AutoSize
        } else {
            Get-PSDrive -PSProvider FileSystem | Format-Table Name, Root, Used, Free -AutoSize
        }
    })) { return }

    $sourceLetter = (Read-Host 'Ky tu o phan vung Windows tham chieu (vi du W)').Trim().TrimEnd(':').ToUpperInvariant()
    $destinationLetter = (Read-Host 'Ky tu o luu file WIM (vi du D)').Trim().TrimEnd(':').ToUpperInvariant()
    if ($sourceLetter -notmatch '^[A-Z]$' -or $destinationLetter -notmatch '^[A-Z]$') {
        Write-Warning 'Ky tu volume phai la mot chu cai A-Z; chay lai va nhap dung drive letter trong WinPE.'
        return
    }
    $defaultImage = "${destinationLetter}:\install.wim"
    $imagePath = (Read-Host "Duong dan image dau ra (.wim hoac .esd) [$defaultImage]").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($imagePath)) { $imagePath = $defaultImage }
    $imagePath = [System.IO.Path]::GetFullPath($imagePath)
    $imageName = Read-Host 'Ten image trong install.wim/install.esd [Windows_Custom]'
    if ([string]::IsNullOrWhiteSpace($imageName)) { $imageName = 'Windows_Custom' }
    $imageDescription = Read-Host 'Mo ta image [Custom Windows image]'
    if ([string]::IsNullOrWhiteSpace($imageDescription)) { $imageDescription = 'Custom Windows image' }
    $compression = (Read-Host 'DISM compression cho WIM trung gian (fast/max) [fast]').Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($compression)) { $compression = 'fast' }
    while ($compression -notin @('fast', 'max')) {
        Write-Warning 'Chi ho tro fast hoac max.'
        $compression = (Read-Host 'Compression (fast/max)').Trim().ToLowerInvariant()
    }
    $checkIntegrity = Read-YesNo 'Them /CheckIntegrity? Co the tang thoi gian I/O.'
    $verifyCapture = Read-YesNo 'Them /Verify? DISM doc xac minh image sau capture va co the tang thoi gian.'
    $sourceRoot = "${sourceLetter}:\"
    $destinationRoot = "${destinationLetter}:\"

    $convertToEsd = [System.IO.Path]::GetExtension($imagePath) -ieq '.esd'
    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra phan vung source, dich va duong dan image' {
        if ($sourceLetter -notmatch '^[A-Z]$' -or $destinationLetter -notmatch '^[A-Z]$') { throw 'Ky tu volume phai la mot chu cai A-Z.' }
        if ($sourceLetter -eq $destinationLetter) { throw 'O luu WIM phai khac o Windows source.' }
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'Windows\System32') -PathType Container)) { throw "Khong tim thay $sourceRoot`Windows\System32. Co the da chon nham volume." }
        if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) { throw "Khong truy cap duoc volume dich $destinationRoot" }
        if ([System.IO.Path]::GetPathRoot($imagePath) -ine $destinationRoot) { throw "Duong dan dau ra phai nam tren volume dich $destinationRoot." }
        if ([System.IO.Path]::GetExtension($imagePath) -inotmatch '^\.(wim|esd)$') { throw 'File dau ra phai co phan mo rong .wim hoac .esd.' }
    })) { return }

    $parent = Split-Path -Parent $imagePath
    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Tao va kiem tra thu muc dich' {
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Khong tao duoc thu muc dich: $parent" }
    })) { return }

    if (Test-Path -LiteralPath $imagePath -PathType Leaf) {
        if (-not (Read-YesNo "Image dich da ton tai ($imagePath). Thay bang image moi sau khi capture va Get-WimInfo deu thanh cong? Ban cu duoc giu lai.")) { Write-Host 'Da huy capture.' -ForegroundColor Yellow; return }
    }
    Write-Host "Source: $sourceRoot`nImage dich cuoi: $imagePath" -ForegroundColor Yellow
    if (-not (Read-YesNo 'Bat dau capture WIM?')) { Write-Host 'Da huy capture.' -ForegroundColor Yellow; return }

    $buildId = [guid]::NewGuid().ToString('N')
    $imageDirectory = Split-Path -Parent $imagePath
    $imageStem = [System.IO.Path]::GetFileNameWithoutExtension($imagePath)
    $captureWim = Join-Path $imageDirectory "$imageStem.capture-$buildId.wim"
    $stagedImagePath = if ($convertToEsd) { Join-Path $imageDirectory "$imageStem.capture-$buildId.esd" } else { $captureWim }
    $checkIntegrityEsd = $false
    if ($convertToEsd) { $checkIntegrityEsd = Read-YesNo 'Them /CheckIntegrity cho buoc export WIM sang ESD? Co the tang I/O.' }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'DISM Capture-Image vao file WIM staging' {
        $captureArguments = @('/Capture-Image', "/ImageFile:$captureWim", "/CaptureDir:$sourceRoot", "/Name:$imageName", "/Description:$imageDescription", "/Compress:$compression")
        if ($checkIntegrity) { $captureArguments += '/CheckIntegrity' }
        if ($verifyCapture) { $captureArguments += '/Verify' }
        $captureFlags = @()
        if ($checkIntegrity) { $captureFlags += '/CheckIntegrity' }
        if ($verifyCapture) { $captureFlags += '/Verify' }
        Write-Host "      Flags: $(if ($captureFlags.Count -gt 0) { $captureFlags -join ' ' } else { '(none)' })" -ForegroundColor DarkGray
        $dismCode = Invoke-DismWithProgress -Activity 'DISM Capture-Image' -Arguments $captureArguments
        if ($dismCode -ne 0 -or -not (Test-Path -LiteralPath $captureWim -PathType Leaf)) { throw "DISM capture that bai (ma loi $dismCode)." }
    })) { $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize; return }

    if ($convertToEsd) {
        $taskNumber++
        if (-not (Invoke-ToolkitTask $taskNumber 'DISM Export WIM staging sang ESD /Compress:recovery' {
            $esdArguments = @('/Export-Image', "/SourceImageFile:$captureWim", '/SourceIndex:1', "/DestinationImageFile:$stagedImagePath", '/Compress:recovery')
            if ($checkIntegrityEsd) { $esdArguments += '/CheckIntegrity' }
            $dismCode = Invoke-DismWithProgress -Activity 'DISM Export-Image /Compress:recovery' -Arguments $esdArguments
            if ($dismCode -ne 0 -or -not (Test-Path -LiteralPath $stagedImagePath -PathType Leaf)) { throw "DISM export ESD that bai (ma loi $dismCode). WIM staging duoc giu lai tai $captureWim" }
        })) { $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize; return }
    }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo kiem tra image staging' {
        & "$env:WINDIR\System32\dism.exe" /Get-WimInfo "/WimFile:$stagedImagePath"
        if ($LASTEXITCODE -ne 0) { throw "DISM Get-WimInfo tren image staging that bai (ma loi $LASTEXITCODE)." }
    })) { $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize; return }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Publish image da kiem tra vao duong dan cuoi' {
        Publish-StagedFile -StagedPath $stagedImagePath -DestinationPath $imagePath
    })) { $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize; return }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo kiem tra lai image tai duong dan cuoi' {
        & "$env:WINDIR\System32\dism.exe" /Get-WimInfo "/WimFile:$imagePath"
        if ($LASTEXITCODE -ne 0) { throw "DISM Get-WimInfo tren image cuoi that bai (ma loi $LASTEXITCODE)." }
    })) { $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize; return }

    if ($convertToEsd) {
        $taskNumber++
        if (-not (Invoke-ToolkitTask $taskNumber 'Xoa WIM capture staging sau khi ESD da publish va verify' {
            Remove-Item -LiteralPath $captureWim -Force -ErrorAction Stop
        })) { $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize; return }
    }
    $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
    Write-Host "Da capture image: $imagePath" -ForegroundColor Green
}

function Invoke-Step4_BuildISO {
    Clear-Host
    Write-Host '=== POST-CAPTURE: THAY INSTALL.WIM/ESD VA SAVE AS ISO ===' -ForegroundColor Cyan
    Write-Host 'AnyBurn/UltraISO duoc thao tac bang giao dien; moi thao tac co checkpoint rieng.' -ForegroundColor DarkGray

    $isoSource = (Read-Host 'Duong dan ISO Windows goc').Trim().Trim('"')
    $capturedImage = (Read-Host 'Duong dan install.wim/install.esd moi').Trim().Trim('"')
    $isoOutput = (Read-Host 'Duong dan ISO dau ra [Windows_Custom.iso]').Trim().Trim('"')
    $isoFolder = (Read-Host 'Thu muc trong ISO chua install.wim/esd [\sources\] (AIO vi du \x64\sources\)').Trim()
    $autounattendPath = (Read-Host 'Duong dan autounattend.xml can them vao goc ISO (Enter de bo qua)').Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($isoSource) -or [string]::IsNullOrWhiteSpace($capturedImage)) {
        Write-Warning 'Can nhap ca duong dan ISO goc va image WIM/ESD moi.'
        return
    }
    if ([string]::IsNullOrWhiteSpace($isoOutput)) { $isoOutput = Join-Path (Get-Location).Path 'Windows_Custom.iso' }
    if ([string]::IsNullOrWhiteSpace($isoFolder)) { $isoFolder = '\sources\' }
    $isoFolder = $isoFolder.Trim('\').Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($isoFolder) -or $isoFolder -match '(^|\\)\.\.(\\|$)' -or $isoFolder -match ':') {
        Write-Warning 'Thu muc trong ISO khong hop le.'
        return
    }
    $isoFolderInImage = '\' + $isoFolder + '\'
    $isoSource = [System.IO.Path]::GetFullPath($isoSource)
    $capturedImage = [System.IO.Path]::GetFullPath($capturedImage)
    $isoOutput = [System.IO.Path]::GetFullPath($isoOutput)
    if (-not [string]::IsNullOrWhiteSpace($autounattendPath)) {
        try { $autounattendPath = [System.IO.Path]::GetFullPath($autounattendPath) }
        catch { Write-Warning "Duong dan autounattend.xml khong hop le: $($_.Exception.Message)"; return }
    }
    $script:BuildIsoAutounattendPath = $autounattendPath
    $outputParent = Split-Path -Parent $isoOutput
    $script:BuildIsoPreviousOutput = $null

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra file ISO/image, duoi file va thu muc dau ra' {
        if (-not (Test-Path -LiteralPath $isoSource -PathType Leaf)) { throw "Khong tim thay ISO goc: $isoSource" }
        if (-not (Test-Path -LiteralPath $capturedImage -PathType Leaf)) { throw "Khong tim thay image moi: $capturedImage" }
        if (-not [string]::IsNullOrWhiteSpace($autounattendPath)) {
            if (-not (Test-Path -LiteralPath $autounattendPath -PathType Leaf)) { throw "Khong tim thay autounattend.xml: $autounattendPath" }
            if ([System.IO.Path]::GetFileName($autounattendPath) -ine 'autounattend.xml') { throw 'File tu dong phai ten chinh xac autounattend.xml de Windows Setup tu tim thay.' }
            $answerFile = [xml](Get-Content -LiteralPath $autounattendPath -Raw -ErrorAction Stop)
            Test-AutounattendForSetup -Document $answerFile
        }
        if ([System.IO.Path]::GetExtension($isoSource) -ine '.iso' -or [System.IO.Path]::GetExtension($isoOutput) -ine '.iso') { throw 'ISO goc va dau ra phai co duoi .iso.' }
        if ([System.IO.Path]::GetExtension($capturedImage) -inotmatch '^\.(wim|esd)$') { throw 'Image moi phai co duoi .wim hoac .esd.' }
        if ([System.IO.Path]::GetFullPath($isoSource) -ieq $isoOutput) { throw 'ISO dau ra phai khac ISO goc.' }
        if ([System.IO.Path]::GetFullPath($capturedImage) -ieq $isoOutput) { throw 'Image khong the la duong dan ISO dau ra.' }
        if ((Get-Item -LiteralPath $capturedImage).Length -lt 1MB) { throw 'Image moi rong hoac nho bat thuong.' }
        if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { New-Item -ItemType Directory -Path $outputParent -Force -ErrorAction Stop | Out-Null }
        if (Test-Path -LiteralPath $isoOutput -PathType Leaf) {
            if (-not (Read-YesNo "ISO dau ra da ton tai ($isoOutput). Ghi de qua Save As? File cu se duoc giu cho den khi ban tu xac nhan ghi de trong AnyBurn/UltraISO.")) { throw 'Nguoi dung huy ghi de ISO.' }
            $script:BuildIsoPreviousOutput = Get-Item -LiteralPath $isoOutput -ErrorAction Stop
        }
    })) { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber "Mount ISO goc va tim install.wim/esd trong $isoFolderInImage" {
        $diskImage = $null
        try {
            $diskImage = Mount-DiskImage -ImagePath $isoSource -PassThru -ErrorAction Stop
            $volume = $diskImage | Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter } | Select-Object -First 1
            if ($null -eq $volume) { throw 'Khong tim thay drive letter cua ISO sau khi mount.' }
            $sourcesPath = Join-Path ("$($volume.DriveLetter):\") $isoFolder
            if (-not (Test-Path -LiteralPath $sourcesPath -PathType Container)) { throw "Khong tim thay folder trong ISO: $isoFolderInImage" }
            if (Test-Path -LiteralPath (Join-Path $sourcesPath 'install.wim') -PathType Leaf) { $script:BuildIsoImageToReplace = 'install.wim' }
            elseif (Test-Path -LiteralPath (Join-Path $sourcesPath 'install.esd') -PathType Leaf) { $script:BuildIsoImageToReplace = 'install.esd' }
            elseif (@(Get-ChildItem -LiteralPath $sourcesPath -Filter 'install*.swm' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'ISO dung install*.swm; toolkit khong thay bo SWM.' }
            else { throw "Khong tim thay install.wim/esd trong $isoFolderInImage." }
            Write-Host "      File se thay: $isoFolderInImage$script:BuildIsoImageToReplace" -ForegroundColor DarkGray
        }
        finally {
            if ($null -ne $diskImage) { Dismount-DiskImage -ImagePath $isoSource -ErrorAction SilentlyContinue | Out-Null }
        }
    })) { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Mo AnyBurn hoac UltraISO tren giao dien' {
        $defaultEditors = @(
            'C:\Program Files\AnyBurn\AnyBurn.exe',
            'C:\Program Files (x86)\AnyBurn\AnyBurn.exe',
            'C:\Program Files\UltraISO\UltraISO.exe',
            'C:\Program Files (x86)\UltraISO\UltraISO.exe'
        )
        $editorPath = $defaultEditors | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $editorPath) { $editorPath = (Read-Host 'Nhap duong dan AnyBurn.exe hoac UltraISO.exe').Trim().Trim('"') }
        if (-not (Test-Path -LiteralPath $editorPath -PathType Leaf)) { throw "Khong tim thay phan mem ISO: $editorPath" }
        Start-Process -FilePath $editorPath -ErrorAction Stop
        Write-Host "      Da mo: $editorPath" -ForegroundColor DarkGray
    })) { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    Invoke-ManualToolkitTask $taskNumber 'Mo ISO goc trong che do Edit image' @(
        "Trong AnyBurn chon Edit image file; trong UltraISO mo ISO goc va mo thu muc $isoFolderInImage.",
        "Chon dung ISO goc: $isoSource. Chua Save As o task nay."
    )
    if ($script:ToolkitTaskResults[-1].Status -ne 'SUCCESS') { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    Invoke-ManualToolkitTask $taskNumber "Xoa file $script:BuildIsoImageToReplace trong ISO goc" @(
        "Trong khung noi dung ISO, xoa rieng file $isoFolderInImage$script:BuildIsoImageToReplace.",
        'Khong xoa folder sources, boot, efi hoac cac file khac.'
    )
    if ($script:ToolkitTaskResults[-1].Status -ne 'SUCCESS') { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    Invoke-ManualToolkitTask $taskNumber "Them image moi vao $isoFolderInImage" @(
        "Add file capture '$capturedImage' vao dung folder $isoFolderInImage.",
        "Ten file ben trong ISO phai la install$([System.IO.Path]::GetExtension($capturedImage).ToLowerInvariant())."
    )
    if ($script:ToolkitTaskResults[-1].Status -ne 'SUCCESS') { Write-PostCaptureTaskSummary; return }

    if (-not [string]::IsNullOrWhiteSpace($autounattendPath)) {
        $taskNumber++
        Invoke-ManualToolkitTask $taskNumber 'Them autounattend.xml vao goc ISO' @(
            "Them '$autounattendPath' vao goc media, cung cap voi setup.exe; khong dat trong sources.",
            'Neu ISO da co autounattend.xml, thay file cu bang file nay. Kiem tra answer file truoc khi dung; DiskConfiguration co the xoa phan vung.'
        )
        if ($script:ToolkitTaskResults[-1].Status -ne 'SUCCESS') { Write-PostCaptureTaskSummary; return }
    }

    $taskNumber++
    Invoke-ManualToolkitTask $taskNumber 'Save As thanh ISO moi' @(
        "Save As dung duong dan: $isoOutput.",
        'Khong ghi de ISO goc. Cho AnyBurn/UltraISO bao hoan tat viec tao image.'
    )
    if ($script:ToolkitTaskResults[-1].Status -ne 'SUCCESS') { Write-PostCaptureTaskSummary; return }

    $taskNumber++
    Invoke-ToolkitTask $taskNumber 'Kiem tra ISO dau ra da duoc tao va co kich thuoc hop le' {
        if (-not (Test-Path -LiteralPath $isoOutput -PathType Leaf)) { throw "Khong tim thay ISO dau ra: $isoOutput" }
        $newOutput = Get-Item -LiteralPath $isoOutput -ErrorAction Stop
        if ($newOutput.Length -lt 100MB) { throw 'ISO dau ra nho bat thuong; hay kiem tra qua trinh Save As.' }
        if ($null -ne $script:BuildIsoPreviousOutput -and
            $newOutput.Length -eq $script:BuildIsoPreviousOutput.Length -and
            $newOutput.LastWriteTimeUtc -eq $script:BuildIsoPreviousOutput.LastWriteTimeUtc) {
            throw 'ISO dau ra cu chua thay doi. Kiem tra lai thao tac Save As va xac nhan ghi de.'
        }
        Write-Host "      ISO dau ra: $isoOutput" -ForegroundColor Green
    } | Out-Null
    $script:BuildIsoPreviousOutput = $null

    Write-PostCaptureTaskSummary
    Write-Host 'Tiep theo chon task Verify ISO de mount va DISM Get-WimInfo tung index.' -ForegroundColor Yellow
}
function Write-PostCaptureTaskSummary {
    if (@($script:ToolkitTaskResults).Count -gt 0) {
        $script:ToolkitTaskResults | Format-Table Number, Status, Name, Duration -AutoSize
    }
}

function Invoke-PostCaptureMapVmdkGuide {
    $script:ToolkitTaskResults = @()
    Invoke-ToolkitTask 1 'Map BACKUP.vmdk tren may host' {
        Write-Host 'May tham chieu da tat sau Sysprep va da capture. Tren VMware host:' -ForegroundColor Yellow
        Write-Host '  1. Mo thu muc chua may ao, nhan phai BACKUP.vmdk -> Map Virtual Disk.'
        Write-Host '  2. Gan mot drive letter de doc file install.wim/install.esd; khong boot lai may tham chieu.'
        Write-Host '  3. Vi du file sau khi map: R:\install.wim. Buoc tiep theo se copy toi D:\LAB\source\<build>\<arch>.'
        if (-not (Read-YesNo 'Da map dia ao va thay file install.wim/install.esd tren drive host?')) {
            throw 'Chua map dia ao. Chay lai task nay sau khi Map Virtual Disk.'
        }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureCopyExports {
    Clear-Host
    Write-Host '=== POST-CAPTURE: COPY FILE EXPORT RA NGOAI MAY THAM CHIEU ===' -ForegroundColor Cyan
    Write-Host 'Neu dung export mac dinh tren volume BACKUP, AppAssociations.xml thuong nam tai <drive>:\WinCustomizer\Exports\AppAssociations.xml.' -ForegroundColor DarkGray
    $associationsSource = (Read-Host 'Duong dan AppAssociations.xml tren BACKUP.vmdk da map').Trim().Trim('"')
    $associationsFolder = (Read-Host 'Thu muc dich [D:\LAB\source\21H1\AppAssociations\x86]').Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($associationsFolder)) { $associationsFolder = 'D:\LAB\source\21H1\AppAssociations\x86' }
    $associationsFolder = [System.IO.Path]::GetFullPath($associationsFolder)
    $associationsDestination = Join-Path $associationsFolder 'AppAssociations.xml'
    $copyLayout = Read-YesNo 'Copy them StartLayout.json/LayoutModification.xml neu file export co ton tai?'
    $layoutSource = ''
    $layoutDestination = ''
    if ($copyLayout) {
        $layoutSource = (Read-Host 'Duong dan StartLayout.json/LayoutModification.xml tren BACKUP.vmdk da map').Trim().Trim('"')
        $layoutDestination = Join-Path $associationsFolder ([System.IO.Path]::GetFileName($layoutSource))
    }

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra AppAssociations.xml va tao thu muc dich tren host' {
        if (-not (Test-Path -LiteralPath $associationsSource -PathType Leaf)) { throw "Khong tim thay AppAssociations.xml: $associationsSource. Kiem tra lai duong dan da chon luc export va drive letter cua BACKUP.vmdk." }
        if (-not (Test-Path -LiteralPath $associationsFolder -PathType Container)) { New-Item -ItemType Directory -Path $associationsFolder -Force -ErrorAction Stop | Out-Null }
        if ([System.IO.Path]::GetFullPath($associationsSource) -ieq [System.IO.Path]::GetFullPath($associationsDestination)) { throw 'Nguon va dich associations la cung mot file.' }
        Write-Host "      Nguon: $associationsSource`n      Dich:  $associationsDestination" -ForegroundColor DarkGray
    })){ Write-PostCaptureTaskSummary; return }

    $associationsStage = Join-Path $associationsFolder (".AppAssociations.copy-$([guid]::NewGuid().ToString('N')).xml")
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Copy va verify AppAssociations.xml trong staging' {
        Copy-Item -LiteralPath $associationsSource -Destination $associationsStage -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $associationsStage -PathType Leaf) -or (Get-Item -LiteralPath $associationsStage).Length -ne (Get-Item -LiteralPath $associationsSource).Length) { throw 'Kiem tra AppAssociations.xml staging that bai.' }
        if ((Get-FileHash -LiteralPath $associationsStage -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $associationsSource -Algorithm SHA256).Hash) { throw 'SHA-256 AppAssociations.xml staging khong khop source.' }
    })) { Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Publish AppAssociations.xml vao thu muc host' {
        Publish-StagedFile -StagedPath $associationsStage -DestinationPath $associationsDestination
        Write-Host "      File host: $associationsDestination" -ForegroundColor Green
    })) { Write-PostCaptureTaskSummary; return }

    if ($copyLayout) {
        $layoutStage = Join-Path $associationsFolder (".$([System.IO.Path]::GetFileName($layoutSource)).copy-$([guid]::NewGuid().ToString('N'))")
        $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Copy va verify Start layout trong staging' {
            if (-not (Test-Path -LiteralPath $layoutSource -PathType Leaf)) { throw "Khong tim thay Start layout: $layoutSource" }
            Copy-Item -LiteralPath $layoutSource -Destination $layoutStage -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $layoutStage -PathType Leaf) -or (Get-Item -LiteralPath $layoutStage).Length -ne (Get-Item -LiteralPath $layoutSource).Length) { throw 'Kiem tra Start layout staging that bai.' }
            if ((Get-FileHash -LiteralPath $layoutStage -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $layoutSource -Algorithm SHA256).Hash) { throw 'SHA-256 Start layout staging khong khop source.' }
        })) { Write-PostCaptureTaskSummary; return }
        $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Publish Start layout vao thu muc host' {
            Publish-StagedFile -StagedPath $layoutStage -DestinationPath $layoutDestination
            Write-Host "      File host: $layoutDestination" -ForegroundColor Green
        })) { Write-PostCaptureTaskSummary; return }
    }
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureCopyImage {
    Clear-Host
    Write-Host '=== POST-CAPTURE: COPY IMAGE TU DIA BACKUP VAO THU MUC BUILD ===' -ForegroundColor Cyan
    Write-Host 'Vi du dung theo bai huong dan: D:\LAB\source\21H1\x86' -ForegroundColor DarkGray
    $sourceImage = (Read-Host 'Duong dan install.wim/install.esd tren dia BACKUP da map').Trim().Trim('"')
    $destinationFolder = (Read-Host 'Thu muc dich tren may host [D:\LAB\source\21H1\x86]').Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($destinationFolder)) { $destinationFolder = 'D:\LAB\source\21H1\x86' }
    if ([string]::IsNullOrWhiteSpace($sourceImage)) { Write-Warning 'Can nhap duong dan file capture tren BACKUP.'; return }
    $sourceImage = [System.IO.Path]::GetFullPath($sourceImage)
    $destinationFolder = [System.IO.Path]::GetFullPath($destinationFolder)
    $imageExtension = [System.IO.Path]::GetExtension($sourceImage).ToLowerInvariant()
    $destinationFile = Join-Path $destinationFolder ('install' + $imageExtension)

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra file capture va duong dan dich' {
        if (-not (Test-Path -LiteralPath $sourceImage -PathType Leaf)) { throw "Khong tim thay file capture: $sourceImage. Hay kiem tra drive letter cua dia BACKUP." }
        if ($imageExtension -notin @('.wim', '.esd')) { throw 'File capture phai co duoi .wim hoac .esd.' }
        if ([System.IO.Path]::GetFullPath($sourceImage) -ieq [System.IO.Path]::GetFullPath($destinationFile)) { throw 'File nguon va file dich dang la mot file.' }
        Write-Host "      Nguon: $sourceImage`n      Dich:  $destinationFile" -ForegroundColor DarkGray
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao va kiem tra thu muc build' {
        if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container)) { New-Item -ItemType Directory -Path $destinationFolder -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container)) { throw "Khong tao duoc thu muc dich: $destinationFolder" }
    })){ Write-PostCaptureTaskSummary; return }

    if ((Test-Path -LiteralPath $destinationFile -PathType Leaf) -and -not (Read-YesNo "File dich da ton tai ($destinationFile). Thay sau khi copy staging duoc verify? Ban cu se duoc giu lai.")) {
        Write-Host 'Da huy copy.' -ForegroundColor Yellow
        Write-PostCaptureTaskSummary
        return
    }
    $stagedCopy = Join-Path $destinationFolder ("install.copy-$([guid]::NewGuid().ToString('N'))$imageExtension")
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Copy capture vao file staging voi thanh tien trinh' {
        Copy-FileWithProgress -SourcePath $sourceImage -StagedPath $stagedCopy -Activity 'Copy capture image'
        Write-Host "      Da copy staging va kich thuoc khop: $stagedCopy" -ForegroundColor DarkGray
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Publish ban staging thanh install.wim/install.esd dich' {
        Publish-StagedFile -StagedPath $stagedCopy -DestinationPath $destinationFile
        if ((Get-Item -LiteralPath $destinationFile -ErrorAction Stop).Length -ne (Get-Item -LiteralPath $sourceImage -ErrorAction Stop).Length) { throw 'Kich thuoc file dich sau publish khong khop nguon.' }
        Write-Host "      Da copy den: $destinationFile" -ForegroundColor Green
    })){ Write-PostCaptureTaskSummary; return }
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureImageInfo {
    $imagePath = (Read-Host 'Duong dan install.wim/install.esd').Trim().Trim('"')
    $script:ToolkitTaskResults = @()
    Invoke-ToolkitTask 1 'DISM Get-WimInfo: kiem tra index, edition, architecture va metadata' {
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) { throw "Khong tim thay image: $imagePath" }
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$imagePath"
        if ($LASTEXITCODE -ne 0) { throw "DISM Get-WimInfo that bai (ma $LASTEXITCODE)." }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureSetMetadata {
    Clear-Host
    Write-Host '=== POST-CAPTURE: IMAGE NAME, DESCRIPTION VA SKU FLAGS ===' -ForegroundColor Cyan
    $imagePath = (Read-Host 'Duong dan install.wim (WIM; khong phai SWM)').Trim().Trim('"')
    $indexText = (Read-Host 'Image index can chinh sua').Trim()
    $newName = Read-Host 'Image Name moi'
    $newDescription = Read-Host 'Description moi'
    $skuFlags = Read-Host 'SKU Flags (vi du Professional, Core, Enterprise; Enter de giu nguyen)'

    $script:ToolkitTaskResults = @()
    if (-not (Invoke-ToolkitTask 1 'Kiem tra file WIM, index va metadata moi' {
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or [System.IO.Path]::GetExtension($imagePath) -ine '.wim') { throw 'Buoc sua metadata can file .wim.' }
        $index = 0
        if (-not [int]::TryParse($indexText, [ref]$index) -or $index -lt 1) { throw 'Index phai la so nguyen duong.' }
        if ([string]::IsNullOrWhiteSpace($newName) -or [string]::IsNullOrWhiteSpace($newDescription)) { throw 'Name va Description khong duoc de trong.' }
        Write-Host "      WIM: $imagePath`n      Index: $index`n      Name: $newName`n      Description: $newDescription`n      Flags: $skuFlags" -ForegroundColor DarkGray
    })) { Write-PostCaptureTaskSummary; return }

    $tool = Get-Command -Name 'wimlib-imagex.exe', 'wimlib-imagex' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $tool) {
        $taskNumber = 2
        Invoke-ToolkitTask $taskNumber 'Ghi metadata bang wimlib-imagex' {
            $arguments = @('info', $imagePath, $indexText, $newName, $newDescription, '--check')
            if (-not [string]::IsNullOrWhiteSpace($skuFlags)) { $arguments += @('--image-property', "FLAGS=$skuFlags") }
            & $tool.Source @arguments
            if ($LASTEXITCODE -ne 0) { throw "wimlib-imagex that bai (ma $LASTEXITCODE)." }
            & $tool.Source 'info' $imagePath $indexText
            if ($LASTEXITCODE -ne 0) { throw 'Khong doc lai duoc metadata sau khi cap nhat.' }
        } | Out-Null
    }
    else {
        $toolPath = (Read-Host 'Nhap duong dan GImageX.exe/NTLite.exe (Enter de huy va bo sung wimlib-imagex)').Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($toolPath)) {
            Write-Warning 'Chua co wimlib-imagex hoac GUI tool. Cai/bo sung tool roi chay lai task; script khong tu sua WIM XML bang lệnh khong duoc ho tro.'
            $script:ToolkitTaskResults += [pscustomobject]@{ Number = 2; Name = 'Ghi metadata bang wimlib/GImageX/NTLite'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Chua co cong cu metadata' }
            Write-PostCaptureTaskSummary
            return
        }
        $taskNumber = 2
        Invoke-ToolkitTask $taskNumber 'Mo GImageX/NTLite de sua metadata rieng cho index' {
            if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Khong tim thay cong cu: $toolPath" }
            Write-Host "      Mo WIM: $imagePath, image index: $indexText" -ForegroundColor Yellow
            Write-Host "      Dat Description='$newDescription' va SKU Flag='$skuFlags', bam Change/Apply; sau do kiem tra tab Info." -ForegroundColor Yellow
            Start-Process -FilePath $toolPath -ErrorAction Stop
            if (-not (Read-YesNo 'Da thay doi metadata cho dung image index va kiem tra lai tab Info?')) { throw 'Chua xac nhan sua va kiem tra metadata.' }
        } | Out-Null
    }
    Write-PostCaptureTaskSummary
}

function Restore-WimFromBackup {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$DestinationWim
    )

    $restoreStage = Join-Path (Split-Path -Parent $DestinationWim) ("install.restore-$([guid]::NewGuid().ToString('N')).wim")
    Copy-FileWithProgress -SourcePath $BackupPath -StagedPath $restoreStage -Activity 'Restore original install.wim'
    Publish-StagedFile -StagedPath $restoreStage -DestinationPath $DestinationWim
    $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
    & $dismPath /Get-WimInfo "/WimFile:$DestinationWim"
    if ($LASTEXITCODE -ne 0) { throw "WIM backup was copied back but Get-WimInfo failed (code $LASTEXITCODE). Backup kept at $BackupPath" }
}

function Invoke-PostCaptureAppendImage {
    Clear-Host
    Write-Host '=== POST-CAPTURE: APPEND THEM IMAGE VAO INSTALL.WIM ===' -ForegroundColor Cyan
    Write-Host 'Nguon WIM va WIM dich phai cung compression. Tao va verify backup truoc khi DISM sua WIM dich.' -ForegroundColor Yellow
    $sourceImage = (Read-Host 'File capture thu hai (install.wim)').Trim().Trim('"')
    $sourceIndexText = (Read-Host 'Source index can export').Trim()
    $destinationWim = (Read-Host 'WIM dich (vi du D:\LAB\source\21H1\x86\install.wim)').Trim().Trim('"')
    $destinationName = Read-Host 'Ten image trong install.wim'
    if ([string]::IsNullOrWhiteSpace($sourceImage) -or [string]::IsNullOrWhiteSpace($destinationWim)) { Write-Warning 'Can nhap file WIM nguon va WIM dich.'; return }
    $sourceImage = [System.IO.Path]::GetFullPath($sourceImage)
    $destinationWim = [System.IO.Path]::GetFullPath($destinationWim)
    $backupDefault = Join-Path (Split-Path -Parent $destinationWim) ("$([System.IO.Path]::GetFileNameWithoutExtension($destinationWim)).pre-append-$([guid]::NewGuid().ToString('N')).wim")
    $backupPath = (Read-Host "Duong dan backup WIM dich [$backupDefault]").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($backupPath)) { $backupPath = $backupDefault }
    $backupPath = [System.IO.Path]::GetFullPath($backupPath)

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra nguon/dich, index va compression' {
        if (-not (Test-Path -LiteralPath $sourceImage -PathType Leaf) -or [System.IO.Path]::GetExtension($sourceImage) -ine '.wim') { throw "Nguon phai la file .wim da capture: $sourceImage" }
        if (-not (Test-Path -LiteralPath $destinationWim -PathType Leaf) -or [System.IO.Path]::GetExtension($destinationWim) -ine '.wim') { throw 'WIM dich phai ton tai va co duoi .wim.' }
        if ([System.IO.Path]::GetFullPath($sourceImage) -ieq [System.IO.Path]::GetFullPath($destinationWim)) { throw 'Source va destination phai la file khac nhau.' }
        if ($backupPath -ieq $sourceImage -or $backupPath -ieq $destinationWim) { throw 'Duong dan backup phai khac WIM nguon va WIM dich.' }
        $sourceIndex = 0
        if (-not [int]::TryParse($sourceIndexText, [ref]$sourceIndex) -or $sourceIndex -lt 1) { throw 'Source index phai la so nguyen duong.' }
        if ([string]::IsNullOrWhiteSpace($destinationName)) { throw 'Ten image dich khong duoc de trong.' }
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo kiem tra source WIM/index' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$sourceImage"
        if ($LASTEXITCODE -ne 0) { throw "Khong doc duoc source WIM (ma $LASTEXITCODE)." }
        Write-Host "      Kiem tra source index $sourceIndexText co trong danh sach tren." -ForegroundColor Yellow
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo kiem tra WIM dich truoc append' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$destinationWim"
        if ($LASTEXITCODE -ne 0) { throw "Khong doc duoc WIM dich truoc append (ma $LASTEXITCODE)." }
    })){ Write-PostCaptureTaskSummary; return }

    if (-not (Read-YesNo 'Da xac nhan source index dung, compression source/destination giong nhau va du disk space? DISM can dung compression; thieu dung luong co the lam loi WIM dich.')) {
        Write-Warning 'Dung truoc khi sao luu/append. Hay xac minh compression va disk space.'
        Write-PostCaptureTaskSummary
        return
    }

    $backupParent = Split-Path -Parent $backupPath
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao va kiem tra thu muc chua backup' {
        if (-not (Test-Path -LiteralPath $backupParent -PathType Container)) { New-Item -ItemType Directory -Path $backupParent -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path -LiteralPath $backupParent -PathType Container)) { throw "Khong tao duoc thu muc backup: $backupParent" }
        if (Test-Path -LiteralPath $backupPath) { throw "File backup da ton tai, khong ghi de: $backupPath" }
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Copy WIM dich thanh backup truoc append voi thanh tien trinh' {
        Copy-FileWithProgress -SourcePath $destinationWim -StagedPath $backupPath -Activity 'Backup install.wim before append'
        Write-Host "      Backup: $backupPath" -ForegroundColor DarkGray
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo verify ban backup WIM' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$backupPath"
        if ($LASTEXITCODE -ne 0) { throw "Backup WIM khong doc duoc (ma $LASTEXITCODE); WIM dich chua bi sua." }
    })){ Write-PostCaptureTaskSummary; return }

    $checkIntegrityAppend = Read-YesNo 'Them /CheckIntegrity vao DISM Export-Image? Co the tang I/O.'
    $taskNumber++
    $appendSucceeded = Invoke-ToolkitTask $taskNumber 'DISM Export-Image append index moi vao WIM dich' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        $arguments = @('/Export-Image', "/SourceImageFile:$sourceImage", "/SourceIndex:$sourceIndexText", "/DestinationImageFile:$destinationWim", "/DestinationName:$destinationName")
        if ($checkIntegrityAppend) { $arguments += '/CheckIntegrity' }
        $dismCode = Invoke-DismWithProgress -Activity "Append image index $sourceIndexText" -Arguments $arguments
        if ($dismCode -ne 0) { throw "DISM Export-Image that bai (ma $dismCode)." }
    }
    if (-not $appendSucceeded) {
        Write-Warning "Append that bai. Ban backup con nguyen tai: $backupPath"
        if (Read-YesNo 'Co phuc hoi WIM dich tu ban backup da verify khong?') {
            $taskNumber++
            Invoke-ToolkitTask $taskNumber 'Restore WIM dich tu backup' { Restore-WimFromBackup -BackupPath $backupPath -DestinationWim $destinationWim } | Out-Null
        }
        Write-PostCaptureTaskSummary
        return
    }

    $taskNumber++
    $verifyAppendSucceeded = Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo xac nhan WIM dich sau append' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$destinationWim"
        if ($LASTEXITCODE -ne 0) { throw "Khong doc duoc WIM sau append (ma $LASTEXITCODE)." }
    }
    if (-not $verifyAppendSucceeded) {
        Write-Warning "Kiem tra WIM dich that bai. Ban backup con nguyen tai: $backupPath"
        if (Read-YesNo 'Co phuc hoi WIM dich tu ban backup da verify khong?') {
            $taskNumber++
            Invoke-ToolkitTask $taskNumber 'Restore WIM dich tu backup' { Restore-WimFromBackup -BackupPath $backupPath -DestinationWim $destinationWim } | Out-Null
        }
        Write-PostCaptureTaskSummary
        return
    }
    Write-Host "Backup ban truoc append: $backupPath" -ForegroundColor Yellow
    Write-Host 'Tiep theo chay task 5 tren index moi de dat Image Name, Description va SKU Flags, roi kiem tra lai.' -ForegroundColor Yellow
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureMountImage {
    Clear-Host
    Write-Host '=== POST-CAPTURE: MOUNT WIM IMAGE DE SERVICING ===' -ForegroundColor Cyan
    $imagePath = (Read-Host 'Duong dan install.wim').Trim().Trim('"')
    $indexText = (Read-Host 'Image index can mount').Trim()
    $mountDirectory = (Read-Host 'Thu muc mount [C:\WinCustomizer\Mount]').Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($mountDirectory)) { $mountDirectory = 'C:\WinCustomizer\Mount' }
    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra WIM, index va thu muc mount rong' {
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or [System.IO.Path]::GetExtension($imagePath) -ine '.wim') { throw 'Mount image can file .wim.' }
        $index = 0
        if (-not [int]::TryParse($indexText, [ref]$index) -or $index -lt 1) { throw 'Index phai la so nguyen duong.' }
        if (-not (Test-Path -LiteralPath $mountDirectory -PathType Container)) { New-Item -ItemType Directory -Path $mountDirectory -Force -ErrorAction Stop | Out-Null }
        if (@(Get-ChildItem -LiteralPath $mountDirectory -Force -ErrorAction Stop).Count -gt 0) { throw "Thu muc mount phai rong: $mountDirectory" }
        Write-Host "      WIM: $imagePath`n      Index: $indexText`n      MountDir: $mountDirectory" -ForegroundColor DarkGray
    })){ Write-PostCaptureTaskSummary; return }
    $taskNumber++; Invoke-ToolkitTask $taskNumber 'DISM Mount-Image' {
        $dismCode = Invoke-DismWithProgress -Activity 'DISM Mount-Image' -Arguments @('/Mount-Image', "/ImageFile:$imagePath", "/Index:$indexText", "/MountDir:$mountDirectory", '/CheckIntegrity')
        if ($dismCode -ne 0) { throw "DISM Mount-Image that bai (ma $dismCode)." }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureImportAssociations {
    Clear-Host
    $mountDirectory = (Read-Host 'Thu muc dang mount (chua Windows\System32)').Trim().Trim('"')
    $associationsFile = (Read-Host 'Duong dan AppAssociations.xml da export tu may tham chieu').Trim().Trim('"')
    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra WIM dang mount va AppAssociations.xml' {
        if (-not (Test-Path -LiteralPath (Join-Path $mountDirectory 'Windows\System32') -PathType Container)) { throw "Thu muc chua image mount khong hop le: $mountDirectory" }
        if (-not (Test-Path -LiteralPath $associationsFile -PathType Leaf)) { throw "Khong tim thay AppAssociations.xml: $associationsFile" }
    })){ Write-PostCaptureTaskSummary; return }
    $taskNumber++; Invoke-ToolkitTask $taskNumber 'DISM Import-DefaultAppAssociations vao image offline' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath "/Image:$mountDirectory" "/Import-DefaultAppAssociations:$associationsFile"
        if ($LASTEXITCODE -ne 0) { throw "DISM import associations that bai (ma $LASTEXITCODE)." }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureCleanCopyProfileDefaults {
    Clear-Host
    Write-Host '=== POST-CAPTURE: DON REGISTRY DEFAULT USER SAU COPYPROFILE ===' -ForegroundColor Cyan
    Write-Host 'Chi chay neu unattend.xml da dung CopyProfile=true; can WIM dang mount va khong duoc unmount truoc.' -ForegroundColor Yellow
    $mountDirectory = (Read-Host 'Thu muc mount install.wim (vi du C:\WinCustomizer\Mount)').Trim().Trim('"')
    $copyProfileWasUsed = Read-YesNo 'Image nay da chay Sysprep voi CopyProfile=true?'
    $script:ToolkitTaskResults = @()
    if (-not $copyProfileWasUsed) {
        $script:ToolkitTaskResults += [pscustomobject]@{ Number = 1; Name = 'Registry cleanup CopyProfile'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'CopyProfile khong duoc su dung' }
        Write-PostCaptureTaskSummary
        return
    }

    try {
        if ([string]::IsNullOrWhiteSpace($mountDirectory)) { throw 'Can nhap thu muc mount WIM.' }
        $mountDirectory = [System.IO.Path]::GetFullPath($mountDirectory).TrimEnd('\')
    }
    catch {
        $script:ToolkitTaskResults += [pscustomobject]@{ Number = 1; Name = 'Validate duong dan mount'; Status = 'FAILED'; Duration = '00:00:00'; Error = $_.Exception.Message }
        Write-PostCaptureTaskSummary
        return
    }
    $hivePath = Join-Path $mountDirectory 'Users\Default\NTUSER.DAT'
    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan WIM van dang mount va Default hive ton tai' {
        if (-not (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue)) { throw 'Can Get-WindowsImage tu DISM PowerShell module de xac nhan mount point.' }
        $mountedImages = @(Get-WindowsImage -Mounted -ErrorAction Stop)
        $matchingMounts = @($mountedImages | Where-Object {
            $_.MountPath -and [System.IO.Path]::GetFullPath($_.MountPath).TrimEnd('\') -ieq $mountDirectory
        })
        if ($matchingMounts.Count -ne 1) { throw "Thu muc '$mountDirectory' khong phai mount point duy nhat trong DISM." }
        if (-not (Test-Path -LiteralPath (Join-Path $mountDirectory 'Windows\System32') -PathType Container)) { throw 'Thu muc mount khong co Windows\System32.' }
        if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) { throw "Khong tim thay Default user hive: $hivePath" }
        Write-Host "      WIM: $($matchingMounts[0].ImagePath) index $($matchingMounts[0].ImageIndex)" -ForegroundColor DarkGray
    })) { Write-PostCaptureTaskSummary; return }

    $hiveName = 'WinCustomizer_Default_' + [guid]::NewGuid().ToString('N')
    $registryHive = "HKU\$hiveName"
    $registryRoot = "Registry::HKEY_USERS\$hiveName"
    $script:CopyProfileHiveLoaded = $false
    try {
        $taskNumber++
        $loadHiveSucceeded = Invoke-ToolkitTask $taskNumber 'Load Users\Default\NTUSER.DAT vao registry tam' {
            & "$env:WINDIR\System32\reg.exe" load $registryHive $hivePath | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "reg.exe load that bai (ma $LASTEXITCODE)." }
            $script:CopyProfileHiveLoaded = $true
            if (-not (Test-Path -LiteralPath $registryRoot)) { throw 'Hive khong xuat hien trong HKEY_USERS sau khi load.' }
        }
        if (-not $loadHiveSucceeded) { Write-PostCaptureTaskSummary; return }

        $taskNumber++; Invoke-ToolkitTask $taskNumber 'Xoa FileAssociationsUpdateVersion khoi Default profile' {
            $associationRoot = Join-Path $registryRoot 'Software\Microsoft\Windows\Shell\Associations'
            $value = Get-ItemProperty -LiteralPath $associationRoot -Name 'FileAssociationsUpdateVersion' -ErrorAction SilentlyContinue
            if ($null -ne $value) { Remove-ItemProperty -LiteralPath $associationRoot -Name 'FileAssociationsUpdateVersion' -ErrorAction Stop }
            $unexpectedKey = Join-Path $associationRoot 'FileAssociationsUpdateVersion'
            if (Test-Path -LiteralPath $unexpectedKey) { Remove-Item -LiteralPath $unexpectedKey -Recurse -Force -ErrorAction Stop }
            if ($null -ne (Get-ItemProperty -LiteralPath $associationRoot -Name 'FileAssociationsUpdateVersion' -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $unexpectedKey)) { throw 'FileAssociationsUpdateVersion van ton tai sau cleanup.' }
            Write-Host '      Registry entry da xoa hoac khong co san.' -ForegroundColor DarkGray
        } | Out-Null

        $taskNumber++; Invoke-ToolkitTask $taskNumber 'Xoa UrlAssociations khoi Default profile' {
            $keyPath = Join-Path $registryRoot 'Software\Microsoft\Windows\Shell\Associations\UrlAssociations'
            if (Test-Path -LiteralPath $keyPath) { Remove-Item -LiteralPath $keyPath -Recurse -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $keyPath) { throw 'UrlAssociations van ton tai sau cleanup.' }
            Write-Host '      Registry key da xoa hoac khong co san.' -ForegroundColor DarkGray
        } | Out-Null

        $taskNumber++; Invoke-ToolkitTask $taskNumber 'Xoa Explorer\FileExts khoi Default profile' {
            $keyPath = Join-Path $registryRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts'
            if (Test-Path -LiteralPath $keyPath) { Remove-Item -LiteralPath $keyPath -Recurse -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $keyPath) { throw 'Explorer\FileExts van ton tai sau cleanup.' }
            Write-Host '      Registry key da xoa hoac khong co san.' -ForegroundColor DarkGray
        } | Out-Null
    }
    finally {
        if ($script:CopyProfileHiveLoaded) {
            $taskNumber++; Invoke-ToolkitTask $taskNumber 'Unload registry tam va giai phong Default hive' {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                & "$env:WINDIR\System32\reg.exe" unload $registryHive | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "reg.exe unload that bai (ma $LASTEXITCODE). Khong unmount WIM cho den khi hive duoc giai phong." }
                if (Test-Path -LiteralPath $registryRoot) { throw 'Registry hive van con loaded sau lenh unload.' }
                $script:CopyProfileHiveLoaded = $false
            } | Out-Null
        }
    }
    Write-PostCaptureTaskSummary
    $failedTasks = @($script:ToolkitTaskResults | Where-Object Status -eq 'FAILED')
    if ($failedTasks.Count -gt 0) { Write-Host 'Co task cleanup loi; khong COMMIT WIM cho den khi da khac phuc hoac chon DISCARD.' -ForegroundColor Red }
    else { Write-Host 'Cleanup CopyProfile hoan tat. Tiep tuc task 10/11 va COMMIT WIM neu cac kiem tra deu thanh cong.' -ForegroundColor Green }
}

function Invoke-PostCaptureVerifyAssociations {
    $mountDirectory = (Read-Host 'Thu muc WIM dang mount').Trim().Trim('"')
    $script:ToolkitTaskResults = @()
    Invoke-ToolkitTask 1 'DISM Get-DefaultAppAssociations kiem tra image offline' {
        if (-not (Test-Path -LiteralPath (Join-Path $mountDirectory 'Windows\System32') -PathType Container)) { throw "Thu muc WIM mount khong hop le: $mountDirectory" }
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath "/Image:$mountDirectory" /Get-DefaultAppAssociations
        if ($LASTEXITCODE -ne 0) { throw "DISM verify associations that bai (ma $LASTEXITCODE)." }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureUnmountImage {
    $mountDirectory = (Read-Host 'Thu muc WIM dang mount').Trim().Trim('"')
    Write-Host 'Nhap COMMIT de luu thay doi hoac DISCARD de huy toan bo thay doi tren WIM.' -ForegroundColor Yellow
    $decision = (Read-Host 'COMMIT/DISCARD').Trim().ToUpperInvariant()
    if ($decision -notin @('COMMIT', 'DISCARD')) { Write-Warning 'Da huy unmount; hay chon COMMIT hoac DISCARD ro rang.'; return }
    $script:ToolkitTaskResults = @()
    Invoke-ToolkitTask 1 "DISM Unmount-Image /$decision" {
        if (-not (Test-Path -LiteralPath $mountDirectory -PathType Container)) { throw "Khong tim thay mount directory: $mountDirectory" }
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        $arguments = @('/Unmount-Image', "/MountDir:$mountDirectory", "/$decision")
        if ($decision -eq 'COMMIT') { $arguments += '/CheckIntegrity' }
        $dismCode = Invoke-DismWithProgress -Activity "DISM Unmount-Image $decision" -Arguments $arguments
        if ($dismCode -ne 0) { throw "DISM Unmount-Image that bai (ma $dismCode)." }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureExportEsd {
    Clear-Host
    Write-Host '=== POST-CAPTURE: EXPORT TO ESD GIU TAT CA INDEX ===' -ForegroundColor Cyan
    Write-Warning 'Can du dung luong cho ESD staging. File dich cu duoc giu nguyen den khi ESD moi export va Get-WimInfo thanh cong.'
    $sourceWim = (Read-Host 'Duong dan WIM nguon').Trim().Trim('"')
    $destinationEsd = (Read-Host 'Duong dan ESD moi (vi du D:\LAB\source\21H1\x86\install.esd)').Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($sourceWim) -or [string]::IsNullOrWhiteSpace($destinationEsd)) { Write-Warning 'Can nhap ca duong dan WIM nguon va ESD dich.'; return }
    $sourceWim = [System.IO.Path]::GetFullPath($sourceWim)
    $destinationEsd = [System.IO.Path]::GetFullPath($destinationEsd)
    $destinationParent = Split-Path -Parent $destinationEsd
    $script:ToolkitTaskResults = @()
    $script:PostCaptureImages = @()
    $script:PostCaptureEsdStagedPath = $null
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra WIM nguon va duong dan ESD dich' {
        if (-not (Test-Path -LiteralPath $sourceWim -PathType Leaf) -or [System.IO.Path]::GetExtension($sourceWim) -ine '.wim') { throw 'Nguon phai la file .wim.' }
        if ([System.IO.Path]::GetExtension($destinationEsd) -ine '.esd') { throw 'Dich phai co duoi .esd.' }
        if ([System.IO.Path]::GetFullPath($sourceWim) -ieq [System.IO.Path]::GetFullPath($destinationEsd)) { throw 'Nguon va dich phai khac nhau.' }
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao va kiem tra thu muc dich ESD' {
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) { New-Item -ItemType Directory -Path $destinationParent -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) { throw "Khong tao duoc thu muc dich: $destinationParent" }
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Doc danh sach toan bo image index trong WIM nguon' {
        $getImages = Get-Command -Name Get-WindowsImage -ErrorAction SilentlyContinue
        if ($null -eq $getImages) { throw 'Khong tim thay Get-WindowsImage (DISM PowerShell module). Chay task nay tren Windows host co DISM module.' }
        $script:PostCaptureImages = @(Get-WindowsImage -ImagePath $sourceWim -ErrorAction Stop | Sort-Object ImageIndex)
        if ($script:PostCaptureImages.Count -eq 0) { throw 'WIM khong co image index nao.' }
        $script:PostCaptureImages | Format-Table ImageIndex, ImageName, ImageDescription -AutoSize
    })){ Write-PostCaptureTaskSummary; return }

    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan ghi de va tao ten staging duy nhat' {
        if ((Test-Path -LiteralPath $destinationEsd -PathType Leaf) -and -not (Read-YesNo "ESD dich da ton tai ($destinationEsd). Thay bang ban moi sau khi export/verify? Ban cu se duoc giu lai.")) { throw 'Nguoi dung huy ghi de ESD.' }
        $buildId = [guid]::NewGuid().ToString('N')
        $esdStem = [System.IO.Path]::GetFileNameWithoutExtension($destinationEsd)
        $script:PostCaptureEsdStagedPath = Join-Path $destinationParent "$esdStem.build-$buildId.esd"
        if (Test-Path -LiteralPath $script:PostCaptureEsdStagedPath) { throw 'Duong dan staging da ton tai, hay chay lai task de tao staging moi.' }
        Write-Host "      ESD staging: $script:PostCaptureEsdStagedPath" -ForegroundColor DarkGray
    })){ Write-PostCaptureTaskSummary; return }

    $checkIntegrityEsd = Read-YesNo 'Them /CheckIntegrity cho moi index khi export ESD? Co the tang I/O.'
    $indexNumber = 0
    foreach ($image in $script:PostCaptureImages) {
        $indexNumber++
        $thisIndex = [int]$image.ImageIndex
        $arguments = @('/Export-Image', "/SourceImageFile:$sourceWim", "/SourceIndex:$thisIndex", "/DestinationImageFile:$script:PostCaptureEsdStagedPath")
        if ($indexNumber -eq 1) { $arguments += '/Compress:recovery' }
        if ($checkIntegrityEsd) { $arguments += '/CheckIntegrity' }
        $taskNumber++
        $exportOk = Invoke-ToolkitTask $taskNumber "DISM Export image index $thisIndex sang ESD (/Compress:recovery)" {
            $dismCode = Invoke-DismWithProgress -Activity "Export ESD index $thisIndex" -Arguments $arguments
            if ($dismCode -ne 0) { throw "DISM Export-Image index $thisIndex that bai (ma $dismCode)." }
        }
        if (-not $exportOk) {
            Write-Host "Dung export, ESD staging duoc giu de kiem tra: $script:PostCaptureEsdStagedPath. ESD dich cu van con nguyen." -ForegroundColor Red
            Write-PostCaptureTaskSummary
            $script:PostCaptureImages = @()
            return
        }
    }
    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Kiem tra toan bo index trong ESD staging' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$script:PostCaptureEsdStagedPath"
        if ($LASTEXITCODE -ne 0) { throw "DISM Get-WimInfo tren ESD that bai (ma $LASTEXITCODE)." }
    })) { Write-PostCaptureTaskSummary; $script:PostCaptureImages = @(); return }

    $taskNumber++
    if (-not (Invoke-ToolkitTask $taskNumber 'Publish ESD staging vao duong dan dich' {
        Publish-StagedFile -StagedPath $script:PostCaptureEsdStagedPath -DestinationPath $destinationEsd
        $script:PostCaptureEsdStagedPath = $null
    })) { Write-PostCaptureTaskSummary; $script:PostCaptureImages = @(); return }

    Write-Host "ESD dau ra: $destinationEsd" -ForegroundColor Green
    $taskNumber++
    Invoke-ToolkitTask $taskNumber 'Kiem tra lai toan bo index tai ESD dich cuoi' {
        $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
        & $dismPath /Get-WimInfo "/WimFile:$destinationEsd"
        if ($LASTEXITCODE -ne 0) { throw "DISM Get-WimInfo tren ESD dich that bai (ma $LASTEXITCODE)." }
    } | Out-Null
    Write-PostCaptureTaskSummary
    $script:PostCaptureImages = @()
    $script:PostCaptureEsdStagedPath = $null
}

function Invoke-PostCaptureVerifyISO {
    Clear-Host
    $isoPath = (Read-Host 'Duong dan ISO can kiem tra').Trim().Trim('"')
    $isoFolder = (Read-Host 'Thu muc trong ISO chua install.wim/esd [\sources\]').Trim()
    $defaultAutounattend = $script:BuildIsoAutounattendPath
    $expectedAutounattendPath = (Read-Host "Duong dan autounattend.xml can verify/hash (Enter de bo qua) [$defaultAutounattend]").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($expectedAutounattendPath)) { $expectedAutounattendPath = $defaultAutounattend }
    if (-not [string]::IsNullOrWhiteSpace($expectedAutounattendPath)) {
        try { $expectedAutounattendPath = [System.IO.Path]::GetFullPath($expectedAutounattendPath) }
        catch { Write-Warning "Duong dan autounattend.xml khong hop le: $($_.Exception.Message)"; return }
    }
    if ([string]::IsNullOrWhiteSpace($isoFolder)) { $isoFolder = '\sources\' }
    $isoFolder = $isoFolder.Trim('\').Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($isoFolder) -or $isoFolder -match '(^|\\)\.\.(\\|$)' -or $isoFolder -match ':') { Write-Warning 'Duong dan thu muc trong ISO khong hop le.'; return }
    $script:ToolkitTaskResults = @()
    $diskImage = $null
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Mount ISO va tim install.wim/esd trong dung thu muc' {
        if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf) -or [System.IO.Path]::GetExtension($isoPath) -ine '.iso') { throw "Khong tim thay file ISO: $isoPath" }
        if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) { throw 'Mount-DiskImage khong co tren may nay.' }
        $diskImage = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
        $volume = $diskImage | Get-Volume -ErrorAction Stop | Where-Object DriveLetter | Select-Object -First 1
        if ($null -eq $volume) { throw 'Khong tim thay drive letter cua ISO.' }
        $script:VerifyMediaRoot = "$($volume.DriveLetter):\"
        $sourceFolder = Join-Path $script:VerifyMediaRoot $isoFolder
        $wim = Join-Path $sourceFolder 'install.wim'
        $esd = Join-Path $sourceFolder 'install.esd'
        if (Test-Path -LiteralPath $wim -PathType Leaf) { $script:VerifyImagePath = $wim }
        elseif (Test-Path -LiteralPath $esd -PathType Leaf) { $script:VerifyImagePath = $esd }
        else { throw "Khong tim thay install.wim/esd trong \$isoFolder" }
        Write-Host "      Image trong ISO: $script:VerifyImagePath" -ForegroundColor DarkGray
    })){ Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null; Write-PostCaptureTaskSummary; return }

    try {
        $taskNumber++
        if (-not [string]::IsNullOrWhiteSpace($expectedAutounattendPath)) {
            Invoke-ToolkitTask $taskNumber 'Kiem tra autounattend.xml o goc ISO va doi chieu SHA-256' {
                if (-not (Test-Path -LiteralPath $expectedAutounattendPath -PathType Leaf)) { throw "Khong tim thay file nguon autounattend.xml: $expectedAutounattendPath" }
                if ([System.IO.Path]::GetFileName($expectedAutounattendPath) -ine 'autounattend.xml') { throw 'File nguon phai co ten autounattend.xml.' }
                $mediaAnswerFile = Join-Path $script:VerifyMediaRoot 'autounattend.xml'
                if (-not (Test-Path -LiteralPath $mediaAnswerFile -PathType Leaf)) { throw 'Khong tim thay autounattend.xml tai goc ISO.' }
                $mediaAnswerDocument = [xml](Get-Content -LiteralPath $mediaAnswerFile -Raw -ErrorAction Stop)
                Test-AutounattendForSetup -Document $mediaAnswerDocument
                $expectedHash = (Get-FileHash -LiteralPath $expectedAutounattendPath -Algorithm SHA256).Hash
                $mediaHash = (Get-FileHash -LiteralPath $mediaAnswerFile -Algorithm SHA256).Hash
                if ($expectedHash -ne $mediaHash) { throw 'SHA-256 autounattend.xml trong ISO khac file da chon.' }
                Write-Host "      SHA-256: $mediaHash" -ForegroundColor DarkGray
            } | Out-Null
        }
        else {
            Write-Host "[$taskNumber] [SKIPPED] Verify autounattend.xml - khong chon file nguon" -ForegroundColor DarkYellow
            $script:ToolkitTaskResults += [pscustomobject]@{ Number = $taskNumber; Name = 'Verify autounattend.xml'; Status = 'SKIPPED'; Duration = '00:00:00'; Error = 'Khong cung cap duong dan file nguon' }
        }

        $taskNumber++; Invoke-ToolkitTask $taskNumber 'DISM Get-WimInfo tren install image trong ISO' {
            $dismPath = Join-Path $env:WINDIR 'System32\dism.exe'
            & $dismPath /Get-WimInfo "/WimFile:$script:VerifyImagePath"
            if ($LASTEXITCODE -ne 0) { throw "DISM Get-WimInfo that bai (ma $LASTEXITCODE)." }
        } | Out-Null
    }
    finally {
        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
        $script:VerifyImagePath = $null
        $script:VerifyMediaRoot = $null
    }
    Write-PostCaptureTaskSummary
}

function Invoke-PostCaptureCreateAutounattend {
    Clear-Host
    Write-Host '=== POST-CAPTURE: TAO AUTOUNATTEND.XML CHON EDITION KHI CAI WINDOWS ===' -ForegroundColor Cyan
    Write-Host 'File gom windowsPE de chon edition va co the tuy chon oobeSystem de cai ProtectYourPC; khong ghi vao Sysprep\unattend.xml.' -ForegroundColor Yellow
    Write-Host 'ProductKey o day chon edition cai dat, khong kich hoat Windows. Key ban quyen nhap vao se duoc ghi ro trong XML.' -ForegroundColor DarkGray
    Write-Host 'ProtectYourPC chi chon Express settings cu; khong dieu khien tung cong tac Privacy moi trong OOBE Windows 11.' -ForegroundColor DarkGray

    $choice = (Read-Host 'Chon 1=Windows 10/11 Pro (generic setup key), 2=nhap key cua ban, 3=khong dua key [1]').Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    while ($choice -notin @('1', '2', '3')) {
        Write-Warning 'Chi chon 1, 2 hoac 3.'
        $choice = (Read-Host 'Lua chon (1/2/3)').Trim()
    }

    $productKey = ''
    switch ($choice) {
        '1' { $productKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T' }
        '2' {
            while ($true) {
                $secureKey = Read-Host 'Nhap product key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)' -AsSecureString
                $keyPointer = [IntPtr]::Zero
                try {
                    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
                    $productKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer).Trim().ToUpperInvariant()
                }
                finally {
                    if ($keyPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer) }
                    $secureKey.Dispose()
                }
                if ($productKey -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') { break }
                Write-Warning 'Key khong dung dinh dang 25 ky tu.'
            }
        }
        '3' { $productKey = '' }
    }

    $protectYourPc = (Read-Host 'OOBE Express settings: 1=bat, 3=tat, Enter=de Windows hoi nguoi dung [Enter]').Trim()
    while ($protectYourPc -notin @('', '1', '3')) {
        Write-Warning 'Chi nhap 1 (bat), 3 (tat), hoac Enter de bo qua setting.'
        $protectYourPc = (Read-Host 'OOBE Express settings (1/3/Enter)').Trim()
    }

    $architecture = (Read-Host 'Kien truc Windows Setup (amd64/x86) [amd64]').Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = 'amd64' }
    while ($architecture -notin @('amd64', 'x86')) {
        Write-Warning 'Chi ho tro amd64 hoac x86.'
        $architecture = (Read-Host 'Kien truc Windows Setup (amd64/x86)').Trim().ToLowerInvariant()
    }

    $defaultOutput = Join-Path $env:USERPROFILE 'Desktop\autounattend.xml'
    $outputPath = (Read-Host "Duong dan luu file [$defaultOutput]").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($outputPath)) { $outputPath = $defaultOutput }
    try { $outputPath = [System.IO.Path]::GetFullPath($outputPath) }
    catch { Write-Warning "Duong dan khong hop le: $($_.Exception.Message)"; return }
    if ([System.IO.Path]::GetFileName($outputPath) -ine 'autounattend.xml') {
        Write-Warning 'Ten file phai la autounattend.xml de Windows Setup tu phat hien tren media.'
        return
    }
    if ((Test-Path -LiteralPath $outputPath -PathType Leaf) -and -not (Read-YesNo "File da ton tai ($outputPath). Ghi ban moi va giu ban cu?")) {
        Write-Host 'Da huy; file cu duoc giu nguyen.' -ForegroundColor Yellow
        return
    }

    $keyXml = ''
    if (-not [string]::IsNullOrWhiteSpace($productKey)) {
        $keyXml = @"
      <ProductKey>
        <Key>$(ConvertTo-XmlText $productKey)</Key>
        <WillShowUI>OnError</WillShowUI>
      </ProductKey>
"@
    }
    $oobePassXml = ''
    if (-not [string]::IsNullOrWhiteSpace($protectYourPc)) {
        $oobePassXml = @"
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <ProtectYourPC>$protectYourPc</ProtectYourPC>
      </OOBE>
    </component>
  </settings>
"@
    }
    $autounattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData>
        <AcceptEula>true</AcceptEula>
$keyXml
      </UserData>
    </component>
  </settings>
$oobePassXml
</unattend>
"@

    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Parse va kiem tra autounattend XML windowsPE/oobeSystem' {
        $document = [xml]$autounattendXml
        Test-AutounattendForSetup -Document $document
    })) { Write-PostCaptureTaskSummary; return }

    $outputDirectory = Split-Path -Parent $outputPath
    $stagePath = Join-Path $outputDirectory ".autounattend.stage-$([guid]::NewGuid().ToString('N')).xml"
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao thu muc dich autounattend.xml' {
        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null }
    })) { Write-PostCaptureTaskSummary; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Tao staging va khoa ACL truoc khi ghi answer file' {
        $stream = [System.IO.File]::Open($stagePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Dispose()
        Set-RestrictedAnswerFileAcl -Path $stagePath
    })) { Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue; Write-PostCaptureTaskSummary; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Ghi staging va doc lai autounattend XML' {
        [System.IO.File]::WriteAllText($stagePath, $autounattendXml, [System.Text.UTF8Encoding]::new($false))
        $stagedDocument = [xml](Get-Content -LiteralPath $stagePath -Raw -ErrorAction Stop)
        Test-AutounattendForSetup -Document $stagedDocument
    })) { Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue; Write-PostCaptureTaskSummary; return }
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Publish autounattend.xml va giu ban cu' {
        Publish-StagedFile -StagedPath $stagePath -DestinationPath $outputPath
        $publishedDocument = [xml](Get-Content -LiteralPath $outputPath -Raw -ErrorAction Stop)
        Test-AutounattendForSetup -Document $publishedDocument
        Set-RestrictedAnswerFileAcl -Path $outputPath
    })) { Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue; Write-PostCaptureTaskSummary; return }

    Write-PostCaptureTaskSummary
    Write-Host "Da tao: $outputPath" -ForegroundColor Green
    if ($choice -eq '1') { Write-Host 'Key generic chon Windows 10/11 Pro; khong kich hoat. Can digital license hoac license hop le de activate.' -ForegroundColor Yellow }
    elseif ($choice -eq '2') { Write-Host 'File chua product key ban vua nhap o dang ro. Khong upload/commit/chia se file nay.' -ForegroundColor Red }
    else { Write-Host 'Khong co ProductKey; Windows Setup co the hoi chon edition hoac dung edition mac dinh cua media.' -ForegroundColor Yellow }
    if ($protectYourPc -eq '1') { Write-Host 'ProtectYourPC=1: yeu cau OOBE ap dung Express settings.' -ForegroundColor Yellow }
    elseif ($protectYourPc -eq '3') { Write-Host 'ProtectYourPC=3: yeu cau OOBE khong ap dung Express settings.' -ForegroundColor Yellow }
    else { Write-Host 'Khong ghi ProtectYourPC; OOBE tu hien lua chon tuong ung neu build Windows co trang nay.' -ForegroundColor DarkGray }
    Write-Host 'Setting nay khong tu dong tat/bat rieng tung muc Privacy cua Windows 11.' -ForegroundColor Yellow
    Write-Host 'Chon task 12 Build ISO va nhap file nay de them vao goc ISO canh setup.exe.' -ForegroundColor Yellow
    $autounattendXml = $null
    $keyXml = $null
    $productKey = $null
}

function Invoke-PostCaptureRemoveExportSource {
    Clear-Host
    Write-Host '=== POST-CAPTURE: XOA BAN APPS ASSOCIATIONS TREN BACKUP SAU KHI DA COPY ===' -ForegroundColor Cyan
    $sourceFile = (Read-Host 'AppAssociations.xml tren BACKUP da map').Trim().Trim('"')
    $hostCopy = (Read-Host 'Ban host da copy/verify (vi du D:\LAB\source\21H1\AppAssociations\x86\AppAssociations.xml)').Trim().Trim('"')
    $script:ToolkitTaskResults = @()
    $taskNumber = 0
    $taskNumber++; if (-not (Invoke-ToolkitTask $taskNumber 'Xac nhan host co ban copy day du truoc khi xoa source' {
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Khong tim thay file tren BACKUP: $sourceFile" }
        if (-not (Test-Path -LiteralPath $hostCopy -PathType Leaf)) { throw "Khong tim thay ban host: $hostCopy" }
        if ((Get-Item -LiteralPath $sourceFile).Length -ne (Get-Item -LiteralPath $hostCopy).Length) { throw 'Kich thuoc ban host khac source tren BACKUP.' }
        if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $hostCopy -Algorithm SHA256).Hash) { throw 'SHA-256 ban host khac source tren BACKUP.' }
        if (-not (Read-YesNo "Xoa source $sourceFile sau khi da xac nhan ban host?")) { throw 'Nguoi dung huy xoa source.' }
    })){ Write-PostCaptureTaskSummary; return }
    $taskNumber++; Invoke-ToolkitTask $taskNumber 'Xoa AppAssociations.xml source tren BACKUP' {
        Remove-Item -LiteralPath $sourceFile -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $sourceFile -PathType Leaf) { throw 'File source van ton tai sau Remove-Item.' }
    } | Out-Null
    Write-PostCaptureTaskSummary
}

function Invoke-Step6_PostCaptureWorkflow {
    $continuePostCapture = $true
    while ($continuePostCapture) {
        Clear-Host
        Write-Host '=================================================' -ForegroundColor Cyan
        Write-Host ' POST-CAPTURE: TUNG TASK RIENG, CO STATUS' -ForegroundColor Yellow
        Write-Host '=================================================' -ForegroundColor Cyan
        Write-Host ' 1. Map BACKUP.vmdk tren host (manual, khong thao tac trong may tham chieu)'
        Write-Host ' 2. Copy AppAssociations.xml/StartLayout tu BACKUP.vmdk toi host'
        Write-Host ' 3. Copy capture vao D:\LAB\source\<build>\<arch> (co % progress)'
        Write-Host ' 4. DISM Get-WimInfo: xem index/edition/architecture'
        Write-Host ' 5. Sua image Name, Description, SKU Flags (wimlib-imagex hoac GImageX/NTLite)'
        Write-Host ' 6. Append image capture vao install.wim (DISM Export-Image; thay thao tac export/no-overwrite cua NTLite)'
        Write-Host ' 7. Mount install.wim index de sua offline'
        Write-Host ' 8. Import AppAssociations.xml vao image dang mount'
        Write-Host ' 9. Cleanup registry Default profile neu da dung CopyProfile (Microsoft khuyen nghi)'
        Write-Host '10. Kiem tra Default App Associations trong image dang mount'
        Write-Host '11. Unmount image: COMMIT hoac DISCARD'
        Write-Host '12. Export tat ca index WIM sang ESD /Compress:recovery'
        Write-Host '13. Thay install.wim/esd bang AnyBurn/UltraISO GUI va Save As tung task'
        Write-Host '14. Mount ISO dau ra va kiem tra install index'
        Write-Host '15. Xoa source AppAssociations.xml tren BACKUP sau khi host copy da verify (tuy chon)'
        Write-Host '16. Tao autounattend.xml chon edition va tuy chon Express settings OOBE'
        Write-Host ' Q. Ve menu chinh'
        Write-Host '=================================================' -ForegroundColor Cyan
        switch ((Read-Host 'Chon mot task post-capture').ToUpperInvariant()) {
            '1' { Invoke-PostCaptureMapVmdkGuide; Pause-Toolkit }
            '2' { Invoke-PostCaptureCopyExports; Pause-Toolkit }
            '3' { Invoke-PostCaptureCopyImage; Pause-Toolkit }
            '4' { Invoke-PostCaptureImageInfo; Pause-Toolkit }
            '5' { Invoke-PostCaptureSetMetadata; Pause-Toolkit }
            '6' { Invoke-PostCaptureAppendImage; Pause-Toolkit }
            '7' { Invoke-PostCaptureMountImage; Pause-Toolkit }
            '8' { Invoke-PostCaptureImportAssociations; Pause-Toolkit }
            '9' { Invoke-PostCaptureCleanCopyProfileDefaults; Pause-Toolkit }
            '10' { Invoke-PostCaptureVerifyAssociations; Pause-Toolkit }
            '11' { Invoke-PostCaptureUnmountImage; Pause-Toolkit }
            '12' { Invoke-PostCaptureExportEsd; Pause-Toolkit }
            '13' { Invoke-Step4_BuildISO; Pause-Toolkit }
            '14' { Invoke-PostCaptureVerifyISO; Pause-Toolkit }
            '15' { Invoke-PostCaptureRemoveExportSource; Pause-Toolkit }
            '16' { Invoke-PostCaptureCreateAutounattend; Pause-Toolkit }
            'Q' { $continuePostCapture = $false }
            default { Write-Host 'Lua chon khong hop le.' -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
    }
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
        Write-Host ' WINDOWS CUSTOMIZER AUTOMATION TOOLKIT 2.9.1' -ForegroundColor Yellow
    Write-Host '=================================================' -ForegroundColor Cyan
        Write-Host ' 1. Export Default Apps/Start layout truoc khi vao Audit'
        Write-Host ' 2. Cleanup Windows trong Audit Mode'
        Write-Host ' 3. Tao Sysprep unattend.xml (locale/OOBE)'
        Write-Host ' 4. Chay final Sysprep /generalize /oobe /shutdown'
        Write-Host ' 5. Capture WIM/ESD trong WinPE'
        Write-Host ' 6. Post-capture: copy, metadata, append, associations, ESD, ISO'
    Write-Host ' Q. Thoat toolkit'
    Write-Host '=================================================' -ForegroundColor Cyan

    switch ((Read-Host 'Chon buoc (1-6 hoac Q)').ToUpperInvariant()) {
        '1' { Invoke-Step1_ExportUserSettings; Pause-Toolkit }
        '2' { Invoke-Step2_CleanInAudit; Pause-Toolkit }
        '3' { Invoke-Step3_GenerateUnattendXml; Pause-Toolkit }
        '4' { Invoke-Step4_RunSysprep; Pause-Toolkit }
        '5' { Invoke-Step5_CaptureWim; Pause-Toolkit }
        '6' { Invoke-Step6_PostCaptureWorkflow }
        'Q' { $continueMenu = $false }
        default { Write-Host 'Lua chon khong hop le.' -ForegroundColor Red; Start-Sleep -Seconds 2 }
    }
}
