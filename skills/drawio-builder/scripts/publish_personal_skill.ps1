param(
    [string]$SourcePath = (Split-Path -Parent $PSScriptRoot),
    [string]$DestinationPath,
    [string]$DrawioExecutable,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$sync = Join-Path $PSScriptRoot 'sync_personal_skill.ps1'

function Invoke-Sync {
    param([string]$Mode)
    $arguments = @('-Mode',$Mode,'-SourcePath',$SourcePath)
    if ($DestinationPath) { $arguments += @('-DestinationPath',$DestinationPath) }
    if ($DrawioExecutable) { $arguments += @('-DrawioExecutable',$DrawioExecutable) }
    if ($Force) { $arguments += '-Force' }
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $engine -NoProfile -File $sync @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prior }
    $text = $lines -join "`n"
    $data = try { $text | ConvertFrom-Json } catch { $null }
    [pscustomobject]@{ ExitCode=$exitCode; Text=$text; Data=$data }
}

$before = Invoke-Sync 'Check'
if ($before.ExitCode -eq 0) {
    [pscustomobject]@{ Mode='Publish'; Passed=$true; Changed=$false; Destination=$before.Data.Destination; Check=$before.Data } | ConvertTo-Json -Depth 9
    exit 0
}
if (-not $before.Data) { throw "Personal skill check failed: $($before.Text)" }

$install = Invoke-Sync 'Install'
if ($install.ExitCode -ne 0) { throw "Personal skill install failed: $($install.Text)" }
$after = Invoke-Sync 'Check'
if ($after.ExitCode -ne 0) { throw "Personal skill verification failed: $($after.Text)" }

[pscustomobject]@{ Mode='Publish'; Passed=$true; Changed=$true; Destination=$after.Data.Destination; Install=$install.Data; Check=$after.Data } | ConvertTo-Json -Depth 9
