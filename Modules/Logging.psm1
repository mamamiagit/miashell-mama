Set-StrictMode -Version Latest

function Save-ToolkitSimulation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,
          [Parameter(Mandatory)][string]$ProfileId,
          [Parameter(Mandatory)][AllowEmptyCollection()][array]$Results)
    if (@($Results | Where-Object { $_.ChangedWindows -ne $false -or $_.Status -ne 'SIMULATED' }).Count -gt 0) {
        throw 'Only simulation records may be saved in Phase 2.'
    }
    $null = New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop
    $path = Join-Path $Directory ('simulation-{0}.json' -f [guid]::NewGuid().ToString('N'))
    [pscustomobject]@{
        SchemaVersion = 1; TimestampUtc = [DateTime]::UtcNow.ToString('o')
        ProfileId = $ProfileId; SimulationOnly = $true; Results = @($Results)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    $path
}

function Get-ToolkitSimulationHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -Filter 'simulation-*.json' | Sort-Object LastWriteTime -Descending)) {
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($record.SimulationOnly -eq $true -and $record.SchemaVersion -eq 1) { $record }
        } catch { Write-Warning "Could not read history file $($file.Name)." }
    }
}

Export-ModuleMember -Function Save-ToolkitSimulation, Get-ToolkitSimulationHistory
