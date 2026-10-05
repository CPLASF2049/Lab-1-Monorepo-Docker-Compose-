<#
    Post-reboot end-to-end validation for lab1-counter (README section 5 / 5.1-5.4).

    Run from a normal PowerShell in the repository root, AFTER Docker Desktop is up:

        cd E:\desktop\lab1-counter
        .\validate.ps1

    Results are appended to docs\acceptance-evidence.txt (also printed to the console).
    The script is non-destructive: it never runs `docker compose down -v` and never
    edits counter values directly in the database.
#>

[CmdletBinding()]
$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot

$report = Join-Path $PSScriptRoot 'docs\acceptance-evidence.txt'
$baseUrl = 'http://localhost:8080'
$failures = New-Object System.Collections.Generic.List[string]

function Log {
    param([string]$Message = '')
    Write-Host $Message
    Add-Content -Path $report -Value $Message -Encoding utf8
}

function Section {
    param([string]$Title)
    Log ''
    Log ('=' * 72)
    Log "== $Title"
    Log ('=' * 72)
}

# Runs a command, echoes "PS> ..." plus its output + exit code into the report.
function Run {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    Log ''
    Log "PS> $Label"
    # Docker writes its progress to stderr; redirecting *only* the native program's
    # stderr (2>&1 placed on the command itself) keeps it as data instead of letting
    # PowerShell turn it into a NativeCommandError record.
    $output = (& $Command 2>&1) | Out-String
    $code = $LASTEXITCODE
    # Strip PowerShell's error-decoration noise if any slipped through.
    $noise = '^\s*\+|^\s*At .*validate\.ps1:\d+|^\s*(CategoryInfo|FullyQualifiedErrorId)\s*:|RemoteException|^\s*(docker|docker\.exe)\s*:\s*$'
    $output = ($output -split "`r?`n" | Where-Object { $_ -notmatch $noise }) -join "`n"
    if ($output.Trim().Length -gt 0) { Log $output.TrimEnd() }
    Log "[exit=$code]"
    return $code
}

function Get-Counter {
    param([string]$Path)
    try {
        $r = Invoke-RestMethod -Uri "$baseUrl$Path" -TimeoutSec 15
        return [int]$r.value
    } catch {
        Log "  !! request $Path failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('increment', 'decrement')][string]$Action,
        [Parameter(Mandatory)][int]$Times,
        [Parameter(Mandatory)][int]$Expected
    )
    $before = Get-Counter '/api/counter'
    for ($i = 1; $i -le $Times; $i++) {
        try {
            $null = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/counter/$Action" -TimeoutSec 15
        } catch {
            Log "  !! POST /api/counter/$Action #$i failed: $($_.Exception.Message)"
        }
    }
    $after = Get-Counter '/api/counter'
    $verdict = if ($after -eq $Expected) { 'PASS' } else { "FAIL (expected $Expected)" }
    if ($after -ne $Expected) { $script:failures.Add("$Name : value=$after expected=$Expected") }
    Log ("[{0}] {1}: {2} -> {3} after {4}x {5}  {6}" -f $verdict, $Name, $before, $after, $Times, $Action, '')
}

function Assert-Value {
    param([string]$Name, [int]$Expected)
    $actual = Get-Counter '/api/counter'
    if ($actual -eq $Expected) {
        Log "[PASS] $Name : value=$actual"
    } else {
        Log "[FAIL] $Name : value=$actual expected=$Expected"
        $script:failures.Add("$Name : value=$actual expected=$Expected")
    }
}

function Db-Value {
    $out = docker compose exec -T db psql -U counter -d counterdb -tAc "SELECT value FROM counter WHERE id = 1;" 2>&1 | Out-String
    return $out.Trim()
}

# ---------------------------------------------------------------------------
Set-Content -Path $report -Value "lab1-counter acceptance evidence - generated $(Get-Date -Format s)" -Encoding utf8

Section '0. Environment'
Run 'git --version' { git --version }
Run 'docker --version' { docker --version }
Run 'docker compose version' { docker compose version }
Run 'docker info (server)' { docker info --format '{{.ServerVersion}} / {{.OSType}} / {{.Name}}' }
Run 'git rev-parse HEAD' { git rev-parse HEAD }
Run 'git rev-parse --abbrev-ref HEAD' { git rev-parse --abbrev-ref HEAD }
Run 'docker volume ls | findstr lab1 (before)' { docker volume ls | Select-String 'lab1' }

$volumeBefore = (docker volume inspect lab1-counter_db-data --format '{{.CreatedAt}}' 2>$null | Out-String).Trim()
Log "db-data CreatedAt (before up): $volumeBefore"

# ---------------------------------------------------------------------------
Section '1. Bring the application up (README 5.1)'
if (-not (Test-Path '.env')) { Run 'copy .env.example .env' { Copy-Item .env.example .env -Force } }
Run 'docker compose config -q' { docker compose config -q }
Run 'docker compose up -d --build' { docker compose up -d --build }
Run 'docker compose ps -a' { docker compose ps -a }

# Wait for the frontend to answer and for the database to be healthy.
Log ''
Log 'waiting for services to become ready (up to 120s)...'
$ready = $false
for ($i = 1; $i -le 60; $i++) {
    try {
        $null = Invoke-RestMethod -Uri "$baseUrl/api/health" -TimeoutSec 5
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}
Log "ready=$ready (after $($i * 2)s)"
Run 'docker compose ps -a (after ready)' { docker compose ps -a }

if (-not $ready) {
    Log 'FATAL: the application did not become ready; see the logs below.'
    Run 'docker compose logs --tail 60 db' { docker compose logs --tail 60 db }
    Run 'docker compose logs --tail 60 backend' { docker compose logs --tail 60 backend }
    Log ''
    Log "RESULT: FAILED - application not ready. See $report"
    exit 1
}

# ---------------------------------------------------------------------------
Section '2. Functional checks (README 5.2)'
Assert-Value 'initial value on first start' 0

# Normalise to a known baseline without ever writing to the database directly.
$baseline = Get-Counter '/api/counter'
if ($baseline -ne 0) {
    Log "  (database already holds $baseline from an earlier run; pressing the button $(-$baseline) times to reach 0 via the API)"
    $action = if ($baseline -gt 0) { 'decrement' } else { 'increment' }
    for ($i = 1; $i -le [Math]::Abs($baseline); $i++) {
        try { $null = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/counter/$action" -TimeoutSec 15 } catch {}
    }
    Assert-Value 'baseline normalised to 0' 0
}

Invoke-Step -Name '+ x3' -Action increment -Times 3 -Expected 3
Invoke-Step -Name '- x1 from 3' -Action decrement -Times 1 -Expected 2
Assert-Value 'after refresh (new GET)' 2
Log "[INFO] open $baseUrl in a second browser / incognito window now: it must show 2 (screenshot this)"

Invoke-Step -Name '- x3 from 2' -Action decrement -Times 3 -Expected -1
Assert-Value 'after refresh (negative value)' -1

Run 'SELECT id, value, updated_at FROM counter' { docker compose exec -T db psql -U counter -d counterdb -c "SELECT id, value, updated_at FROM counter;" }
$dbNow = Db-Value
Log "db value (expected -1): $dbNow"
if ($dbNow -ne '-1') { $failures.Add("db value after -1 step: $dbNow expected -1") }

# ---------------------------------------------------------------------------
Section '3. Service restart (README 5.3)'
Run 'docker compose restart' { docker compose restart }
Start-Sleep -Seconds 10
for ($i = 1; $i -le 30; $i++) {
    try { $null = Invoke-RestMethod -Uri "$baseUrl/api/health" -TimeoutSec 5; break } catch { Start-Sleep -Seconds 2 }
}
Run 'docker compose ps -a' { docker compose ps -a }
Assert-Value 'after docker compose restart' -1
Invoke-Step -Name '+ x1 from -1 (writes after restart)' -Action increment -Times 1 -Expected 0

# ---------------------------------------------------------------------------
Section '4. Delete containers and recreate (README 5.4)'
Invoke-Step -Name '+ x7 to reach 7' -Action increment -Times 7 -Expected 7
Run 'docker compose exec db psql (value before down)' { docker compose exec -T db psql -U counter -d counterdb -c "SELECT id, value FROM counter;" }

Run 'docker compose ps -a (before down)' { docker compose ps -a }
Run 'docker compose down' { docker compose down }
Run 'docker compose ps -a (after down, containers must be gone)' { docker compose ps -a }
Run 'docker volume ls | findstr lab1 (after down, volume must remain)' { docker volume ls | Select-String 'lab1' }
$volumeAfter = (docker volume inspect lab1-counter_db-data --format '{{.CreatedAt}}' 2>$null | Out-String).Trim()
Log "db-data CreatedAt (after down): $volumeAfter"
if ($volumeBefore -and $volumeAfter -and ($volumeBefore -ne $volumeAfter)) {
    $failures.Add('named volume was recreated (CreatedAt changed)')
    Log '[FAIL] named volume was recreated: CreatedAt changed'
} else {
    Log '[PASS] named volume preserved across docker compose down'
}

Run 'docker compose up -d --build (recreate)' { docker compose up -d --build }
Run 'docker compose ps -a (after recreate)' { docker compose ps -a }
$ready = $false
for ($i = 1; $i -le 60; $i++) {
    try { $null = Invoke-RestMethod -Uri "$baseUrl/api/health" -TimeoutSec 5; $ready = $true; break } catch { Start-Sleep -Seconds 2 }
}
Log "ready after recreate=$ready"
Assert-Value 'after container recreation' 7
$dbRecreated = Db-Value
Log "db value after recreation (expected 7): $dbRecreated"
if ($dbRecreated -ne '7') { $failures.Add("db value after recreation: $dbRecreated expected 7") }

Invoke-Step -Name '-1 after recreation' -Action decrement -Times 1 -Expected 6
Assert-Value 'after refresh (new GET, expected 6)' 6
Run 'SELECT id, value FROM counter (final)' { docker compose exec -T db psql -U counter -d counterdb -c "SELECT id, value, updated_at FROM counter;" }
$dbFinal = Db-Value
Log "db value final (expected 6): $dbFinal"

# ---------------------------------------------------------------------------
Section '5. Container status summary'
Run 'docker compose ps -a (final)' { docker compose ps -a }
Run 'docker compose images' { docker compose images }

Section 'RESULT'
if ($failures.Count -eq 0) {
    Log 'ALL CHECKS PASSED'
    Log "Evidence written to $report"
    Log 'Still to add manually: screenshots (docs/images/) and CodeArts project evidence.'
    exit 0
} else {
    Log "FAILURES ($($failures.Count)):"
    foreach ($f in $failures) { Log " - $f" }
    Log "Evidence written to $report"
    exit 1
}
