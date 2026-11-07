Set-StrictMode -Version Latest

function Get-ToolkitSystemInfo {
    [CmdletBinding()]
    param()
    $onWindows = $env:OS -eq 'Windows_NT'
    $info = [ordered]@{
        IsWindows = $onWindows; OS = [Environment]::OSVersion.VersionString
        Build = 0; CPU = 'Unavailable'; GPU = 'Unavailable'; RAM = 'Unavailable'
        Storage = 'Unavailable'; PowerPlan = 'Unavailable'; Administrator = $false
        GamingSettings = 'Not detected in Phase 1'; Warnings = @()
    }
    if (-not $onWindows) {
        $info.Warnings += 'Non-Windows host: UI preview only; Windows hardware data unavailable.'
        return [pscustomobject]$info
    }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $info.OS = $os.Caption
        $info.Build = [int]$os.BuildNumber
        $info.RAM = '{0:N1} GB' -f ($os.TotalVisibleMemorySize / 1MB)
    } catch { $info.Warnings += 'Windows version or memory query failed.' }
    try { $info.CPU = (@(Get-CimInstance Win32_Processor -ErrorAction Stop).Name -join ', ') }
    catch { $info.Warnings += 'CPU query failed.' }
    try { $info.GPU = (@(Get-CimInstance Win32_VideoController -ErrorAction Stop).Name -join ', ') }
    catch { $info.Warnings += 'GPU query failed.' }
    try {
        $info.Storage = (@(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | ForEach-Object {
            '{0} ({1:N0} GB)' -f $_.Model, ($_.Size / 1GB)
        }) -join ', ')
    } catch { $info.Warnings += 'Storage query failed.' }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $info.Administrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $info.Warnings += 'Administrator status could not be determined.' }
    try {
        $plan = Get-CimInstance -Namespace root/cimv2/power -ClassName Win32_PowerPlan -ErrorAction Stop |
            Where-Object { $_.IsActive } | Select-Object -First 1
        if ($null -ne $plan) { $info.PowerPlan = $plan.ElementName }
    } catch { $info.Warnings += 'Active power plan query failed.' }
    [pscustomobject]$info
}

Export-ModuleMember -Function Get-ToolkitSystemInfo
