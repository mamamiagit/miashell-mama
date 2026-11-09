Set-StrictMode -Version Latest

function Get-ToolkitBackupStatus {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Available=$true; Message='Phase 4 supports checksummed atomic session backups. Native changes require local validation; simulation logs are not backups.' }
}

function Get-ToolkitContext {
    [CmdletBinding()]
    param([ValidateSet('Native','Fixture')][string]$Backend='Native')
    if ($Backend -eq 'Fixture') { return [pscustomobject]@{Backend='Fixture';Machine='Fixture';User='Fixture';Build=0} }
    if ($env:OS -ne 'Windows_NT') { throw 'Native sessions require Windows.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    [pscustomobject]@{Backend='Native';Machine=[Environment]::MachineName;User=$identity.User.Value;Build=[Environment]::OSVersion.Version.Build}
}

function Get-ToolkitDigest {
    param([Parameter(Mandatory)][string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-ToolkitDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $payload=$Value | ConvertTo-Json -Depth 20 -Compress
    $json=[pscustomobject]@{Payload=$payload;SHA256=(Get-ToolkitDigest $payload)} | ConvertTo-Json -Compress
    $parent=Split-Path $Path -Parent
    $null=New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
    $temporary=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.tmp')
    $stream=$null
    try {
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $bytes=[Text.Encoding]::UTF8.GetBytes($json)
        $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream=$null
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
        # Verify persistence before the caller may perform any preference write.
        $null=Read-ToolkitDocument -Path $Path
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Read-ToolkitDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -gt 4MB) { throw 'Backup exceeds size limit.' }
    $envelope=[IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json -ErrorAction Stop
    if ($envelope.Payload -isnot [string] -or (Get-ToolkitDigest $envelope.Payload) -cne $envelope.SHA256) { throw 'Backup checksum mismatch.' }
    $envelope.Payload | ConvertFrom-Json -ErrorAction Stop
}

function Get-ToolkitSessionPath {
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$SessionId)
    if ($SessionId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid session ID.' }
    Join-Path (Join-Path ([IO.Path]::GetFullPath($Directory)) 'Sessions') ($SessionId+'.json')
}

function Read-ToolkitSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$SessionId,
          [Parameter(Mandatory)]$Context)
    $record=Read-ToolkitDocument -Path (Get-ToolkitSessionPath -Directory $Directory -SessionId $SessionId)
    if ($record.SchemaVersion -ne 1 -or $record.SessionId -cne $SessionId) { throw 'Unsupported or mismatched backup schema.' }
    foreach ($field in @('Backend','Machine','User')) {
        if ($record.Context.$field -cne $Context.$field) { throw "Backup context mismatch: $field" }
    }
    if ($record.Status -notin @('Prepared','Applying','Completed','Failed','RecoveryRequired','Restoring','Restored','PartialRestore')) { throw 'Invalid session status.' }
    if ($record.Validation -isnot [bool]) { throw 'Invalid validation flag.' }
    $seen=@{}
    foreach ($entry in @($record.Entries)) {
        if ($entry.Id -notin @('mouse','animations') -or $seen.ContainsKey($entry.Id)) { throw 'Invalid or duplicate backup operation.' }
        $seen[$entry.Id]=$true
        if ($entry.State -notin @('Prepared','Applying','Applied','Failed','Restoring','Restored','Conflict','Unverified')) { throw 'Invalid backup operation state.' }
        $original=ConvertTo-ToolkitOperationValue -OperationId $entry.Id -Value $entry.Original
        $target=ConvertTo-ToolkitOperationValue -OperationId $entry.Id -Value $entry.Target
        if ($entry.Id -eq 'mouse') {
            if ($target.Acceleration -ne 0 -or $target.Threshold1 -ne $original.Threshold1 -or $target.Threshold2 -ne $original.Threshold2) { throw 'Invalid mouse target in backup.' }
        } elseif ($target.MinAnimate -ne 0) { throw 'Invalid animation target in backup.' }
    }
    if (@($record.Entries).Count -eq 0) { throw 'Empty session backup.' }
    $record
}

function Save-ToolkitSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Record,
          [Parameter(Mandatory)][string]$Event)
    $Record.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    $Record.Events=@($Record.Events)+@([pscustomobject]@{Utc=$Record.UpdatedUtc;Message=$Event})
    $path=Get-ToolkitSessionPath -Directory $Directory -SessionId $Record.SessionId
    Write-ToolkitDocument -Path $path -Value $Record
    $null=Read-ToolkitSession -Directory $Directory -SessionId $Record.SessionId -Context $Record.Context
}

function Get-ToolkitSessionHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Context)
    $folder=Join-Path $Directory 'Sessions'
    if (-not (Test-Path -LiteralPath $folder)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.json' | Sort-Object LastWriteTime -Descending)) {
        try { Read-ToolkitSession -Directory $Directory -SessionId $file.BaseName -Context $Context }
        catch { Write-Warning "Unreadable or incompatible session $($file.BaseName); it was not used." }
    }
}

function Enter-ToolkitSessionLock {
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Context)
    $null=New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop
    $mutex=$null; $stream=$null; $acquired=$false
    try {
        if ($Context.Backend -eq 'Native') {
            $name='Local\WindowsPerformanceToolkit-'+(Get-ToolkitDigest ($Context.Machine+'|'+$Context.User))
            $mutex=New-Object Threading.Mutex($false,$name)
            try { $acquired=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired=$true }
            if (-not $acquired) { throw 'Another toolkit operation is active in this desktop session.' }
        }
        $stream=[IO.File]::Open((Join-Path $Directory 'session.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        [pscustomobject]@{Stream=$stream;Mutex=$mutex;Acquired=$acquired}
    } catch {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $mutex) { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
        throw
    }
}

function Exit-ToolkitSessionLock {
    param([Parameter(Mandatory)]$Lock)
    $Lock.Stream.Dispose()
    if ($null -ne $Lock.Mutex) { if ($Lock.Acquired) { $Lock.Mutex.ReleaseMutex() }; $Lock.Mutex.Dispose() }
}

Export-ModuleMember -Function Get-ToolkitBackupStatus, Get-ToolkitContext, Get-ToolkitDigest, Write-ToolkitDocument, Read-ToolkitDocument, Get-ToolkitSessionPath, Read-ToolkitSession, Save-ToolkitSession, Get-ToolkitSessionHistory, Enter-ToolkitSessionLock, Exit-ToolkitSessionLock
