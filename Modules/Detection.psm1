Set-StrictMode -Version Latest

function Get-ToolkitRegistryValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    try {
        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        [pscustomobject]@{ State='Known'; Value=$property.$Name; Source="$Path / $Name"; Detail='Stored preference; policy or Windows version may affect effective behavior.' }
    } catch [System.Management.Automation.ItemNotFoundException] {
        [pscustomobject]@{ State='Missing'; Value=$null; Source="$Path / $Name"; Detail='Not explicitly configured. No default is assumed.' }
    } catch [System.Management.Automation.PSArgumentException] {
        [pscustomobject]@{ State='Missing'; Value=$null; Source="$Path / $Name"; Detail='Value absent. No default is assumed.' }
    } catch {
        [pscustomobject]@{ State='Error'; Value=$null; Source="$Path / $Name"; Detail='Could not read setting (access, provider, or other query error). No default is assumed.' }
    }
}

function Get-ToolkitObservations {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$SystemInfo)
    $data = @{}
    if (-not $SystemInfo.IsWindows) { return $data }
    # Fixed, reviewed reads only: no registry paths or commands from JSON.
    $reads = @(
        @('game-mode','HKCU:\Software\Microsoft\GameBar','AutoGameModeEnabled'),
        @('game-dvr','HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR','AppCaptureEnabled'),
        @('dvr-background','HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR','HistoricalCaptureEnabled'),
        @('dvr-policy','HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR','AllowGameDVR'),
        @('dvr-mdm','HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\ApplicationManagement','AllowGameDVR'),
        @('hags','HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers','HwSchMode'),
        @('mouse','HKCU:\Control Panel\Mouse','MouseSpeed'),
        @('animations','HKCU:\Control Panel\Desktop\WindowMetrics','MinAnimate'),
        @('transparency','HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency'),
        @('advertising','HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo','Enabled'),
        @('advertising-policy','HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo','DisabledByGroupPolicy'),
        @('suggestions','HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy','TailoredExperiencesWithDiagnosticDataEnabled'),
        @('diagnostics','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection','AllowTelemetry'),
        @('diagnostics-policy','HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','AllowTelemetry'),
        @('widgets','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarDa'),
        @('widgets-policy','HKLM:\SOFTWARE\Policies\Microsoft\Dsh','AllowNewsAndInterests'),
        @('active-start','HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings','ActiveHoursStart'),
        @('active-end','HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings','ActiveHoursEnd')
    )
    foreach ($read in $reads) { $data[$read[0]] = Get-ToolkitRegistryValue -Path $read[1] -Name $read[2] }
    $data
}

function Get-ToolkitHagsSupport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$SystemInfo, [string]$DxDiagPath)
    $result = [pscustomobject]@{ State='Unknown'; Detail='GPU name and driver version alone do not establish HAGS support. Optionally import a fresh dxdiag XML report.' }
    if (-not $SystemInfo.IsWindows -or $SystemInfo.Build -lt 19041) {
        $result.State='Unsupported'; $result.Detail='Requires Windows 10 build 19041 or later and a compatible GPU/driver.'
        return $result
    }
    if ([string]::IsNullOrWhiteSpace($DxDiagPath)) { return $result }
    $reader = $null
    try {
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = 4MB
        $reader = [System.Xml.XmlReader]::Create((Resolve-Path -LiteralPath $DxDiagPath -ErrorAction Stop).ProviderPath, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        if ($null -eq $SystemInfo.PSObject.Properties['GPUDetails'] -or @($SystemInfo.GPUDetails).Count -eq 0) {
            $result.Detail='Cannot match report to detected GPU drivers.'; return $result
        }
        $supported = 0; $unsupported = 0
        foreach ($gpu in $SystemInfo.GPUDetails) {
            $adapterMatches = @($document.SelectNodes('/DxDiag/DisplayDevices/DisplayDevice') | Where-Object {
                $name = $_.SelectSingleNode('CardName'); $driver = $_.SelectSingleNode('DriverVersion')
                $null -ne $name -and $null -ne $driver -and $name.InnerText -eq $gpu.Name -and $driver.InnerText -eq $gpu.DriverVersion
            })
            if ($adapterMatches.Count -ne 1) { $result.Detail='Report is stale, ambiguous, or does not match every detected GPU/driver.'; return $result }
            $scheduling = $adapterMatches[0].SelectSingleNode('HardwareScheduling')
            $model = $adapterMatches[0].SelectSingleNode('DriverModel')
            if ($null -eq $scheduling -or $null -eq $model) { return $result }
            if ($model.InnerText -notmatch 'WDDM\s+(\d+\.\d+)') { return $result }
            $wddm = [version]$Matches[1]
            if ($scheduling.InnerText -match 'DriverSupportState:Stable\b' -and $wddm -ge [version]'2.7') { $supported++ }
            elseif ($scheduling.InnerText -match 'DriverSupportState:(NotSupported|Unsupported)\b' -or $wddm -lt [version]'2.7') { $unsupported++ }
            else { return $result }
        }
        if ($supported -gt 0 -and $unsupported -eq 0) {
            $result.State='Supported'; $result.Detail='Matching imported dxdiag report indicates stable HAGS support on all detected adapters. Re-export after driver/hardware changes; test both settings.'
        } elseif ($supported -eq 0 -and $unsupported -gt 0) {
            $result.State='Unsupported'; $result.Detail='Matching report indicates no HAGS-capable adapter.'
        } else { $result.Detail='Mixed multi-GPU support; review Windows Graphics settings manually.' }
    } catch { $result.Detail='Could not validate dxdiag XML. Use a fresh XML report; no support is assumed.' }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
    $result
}

Export-ModuleMember -Function Get-ToolkitRegistryValue, Get-ToolkitObservations, Get-ToolkitHagsSupport
