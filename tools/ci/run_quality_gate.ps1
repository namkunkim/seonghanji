[CmdletBinding()]
param(
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$LogDirectory = (Join-Path $PSScriptRoot '..\..\out\quality-gate')
)

# Godot writes benign platform diagnostics to stderr (for example a missing
# Windows root-certificate store).  Native stderr must be logged, not promoted
# by PowerShell into a terminating NativeCommandError before its exit code is
# recorded.
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$GodotBin = (Resolve-Path $GodotBin).Path
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

# Godot 4.7 Windows has no --user-data-dir CLI option.  Its user:// root is
# derived from APPDATA, so isolate it for both local runs and CI.  CI may give
# a per-job root through GODOT_USER_DATA_DIR; it must be writable.
$userDataRoot = if ($env:GODOT_USER_DATA_DIR) { $env:GODOT_USER_DATA_DIR } else { Join-Path $LogDirectory 'user-data' }
$userDataRoot = [IO.Path]::GetFullPath($userDataRoot)
New-Item -ItemType Directory -Force -Path $userDataRoot | Out-Null
$env:APPDATA = $userDataRoot
$env:LOCALAPPDATA = $userDataRoot

$results = [System.Collections.Generic.List[object]]::new()
function Invoke-GateStage {
    param([string]$Name, [string[]]$Arguments)
    $started = Get-Date
    $safeName = $Name -replace '[^A-Za-z0-9_-]', '_'
    $logPath = Join-Path $LogDirectory ("{0:yyyyMMdd-HHmmss}-{1}.log" -f $started, $safeName)
    Write-Host "`n=== $Name ==="
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $GodotBin @Arguments 2>&1 | Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    $ended = Get-Date
    $results.Add([PSCustomObject]@{
        Name = $Name; Started = $started; Ended = $ended
        Duration = [math]::Round(($ended - $started).TotalSeconds, 2)
        ExitCode = $exitCode; Status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        Log = $logPath
    })
}

$version = & $GodotBin --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2') {
    throw "Godot 4.7.2 stable is required; received '$version'."
}
Write-Host "Godot: $version"
Write-Host "Isolated user data root: $userDataRoot"

Push-Location $projectRoot
try {
    # Keep this exact ordered list synchronized with .github/workflows/quality-gate.yml.
    Invoke-GateStage 'import' @('--headless', '--path', '.', '--import')
    Invoke-GateStage 'unit-tests' @('--headless', '--path', '.', '--script', 'tests/run_tests.gd')
    Invoke-GateStage 'campaign-locked-100' @('--headless', '--path', '.', '--script', 'tests/run_campaign.gd')
    Invoke-GateStage 'verify-power' @('--headless', '--path', '.', '--script', 'tests/verify_power.gd')
    Invoke-GateStage 'verify-budget' @('--headless', '--path', '.', '--script', 'tests/verify_budget.gd')
    Invoke-GateStage 'verify-chibi' @('--headless', '--path', '.', '--script', 'tests/verify_chibi.gd')
    Invoke-GateStage 'verify-glyphs' @('--headless', '--path', '.', '--script', 'tests/verify_glyphs.gd')
    Invoke-GateStage 'save-restore' @('--headless', '--path', '.', '--script', 'tests/run_save_restore.gd')
    Invoke-GateStage 'campaign-replay' @('--headless', '--path', '.', '--script', 'tests/run_campaign_replay.gd')
    Invoke-GateStage 'a05-formation' @('--headless', '--path', '.', '--script', 'tests/test_a05_formation_combat.gd')
    Invoke-GateStage 'g10-red-cliffs-e2e' @('--headless', '--path', '.', '--script', 'tests/test_g10_qa01_red_cliffs_entry_e2e.gd')
} finally {
    Pop-Location
}

$summaryPath = Join-Path $LogDirectory 'summary.json'
$results | ConvertTo-Json | Set-Content -Encoding utf8 $summaryPath
Write-Host "`n=== Quality gate summary ==="
$results | Format-Table Name, Started, Ended, Duration, ExitCode, Status, Log -AutoSize | Out-String | Write-Host
Write-Host "Summary: $summaryPath"

$failed = @($results | Where-Object Status -eq 'FAIL')
if ($failed.Count -gt 0) {
    Write-Error ("Quality gate failed: " + ($failed.Name -join ', '))
    exit 1
}
exit 0
