<#
 run_tests.ps1 - chay toan bo kiem thu cua do an EV Charging va luu ket qua.
 Cach dung (trong thu muc chua run_tests.ps1, da kich hoat .venv):
     .\run_tests.ps1
     .\run_tests.ps1 -PgUser postgres -DbName evt_test
 Ket qua: thu muc ket_qua\<thoi gian>\ gom sql_tests.txt, pytest.txt, bao_cao.html, tom_tat.txt
#>
param(
    [string]$PgUser = "postgres",
    [string]$PgHost = "localhost",
    [int]   $PgPort = 5432,
    [string]$DbName = "evt_test",
    [switch]$SkipSql,
    [switch]$SkipPytest
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"
Set-Location $PSScriptRoot

$stamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $PSScriptRoot "ket_qua\$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$summary = New-Object System.Collections.Generic.List[string]
$failed  = $false

# ------------------------------------------------------------ 1. SQL tests
if (-not $SkipSql) {
    Write-Host "`n=== 1. Kiem thu CSDL (tests.sql) ===" -ForegroundColor Cyan
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        Write-Host "Khong tim thay psql. Them thu muc bin cua PostgreSQL vao PATH." -ForegroundColor Red
        $summary.Add("SQL: BO QUA (khong co psql)"); $failed = $true
    } else {
        if (-not $env:PGPASSWORD) {
            $sec = Read-Host "Mat khau PostgreSQL cho user '$PgUser'" -AsSecureString
            $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
        }
        $conn = @("-h", $PgHost, "-p", $PgPort, "-U", $PgUser)
        $log  = Join-Path $outDir "sql_tests.txt"

        # tao lai CSDL test sach, nap schema.sql (tests.sql tu chen du lieu va ROLLBACK)
        & dropdb   @conn --if-exists $DbName 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object $log
        & createdb @conn $DbName            2>&1 | ForEach-Object { $_.ToString() } | Tee-Object $log -Append
        & psql @conn -d $DbName -v ON_ERROR_STOP=1 -f schema.sql 2>&1 |
            ForEach-Object { $_.ToString() } | Out-File (Join-Path $outDir "schema_load.txt") -Encoding utf8
        $schemaCode = $LASTEXITCODE
        if ($schemaCode -ne 0) {
            Write-Host "Nap schema.sql that bai (xem schema_load.txt)." -ForegroundColor Red
            $summary.Add("SQL: LOI nap schema.sql"); $failed = $true
        } else {
            & psql @conn -d $DbName -v ON_ERROR_STOP=1 -f tests.sql 2>&1 |
                ForEach-Object { $_.ToString() } | Tee-Object $log -Append
            $sqlCode = $LASTEXITCODE
            $text = Get-Content $log -Raw
            $pass = ([regex]::Matches($text, "PASS\s")).Count
            $fail = ([regex]::Matches($text, "FAIL\s")).Count
            if ($sqlCode -eq 0 -and $fail -eq 0) {
                Write-Host "SQL: DAT ($pass kiem thu)" -ForegroundColor Green
                $summary.Add("SQL: DAT - $pass PASS, 0 FAIL")
            } else {
                Write-Host "SQL: CO LOI ($pass PASS, $fail FAIL, exit $sqlCode)" -ForegroundColor Red
                $summary.Add("SQL: LOI - $pass PASS, $fail FAIL, exit $sqlCode"); $failed = $true
            }
        }
    }
}

# ------------------------------------------------------------ 2. pytest
if (-not $SkipPytest) {
    Write-Host "`n=== 2. Kiem thu ung dung Flask (pytest) ===" -ForegroundColor Cyan
    $py = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { $py = "python" }
    $log = Join-Path $outDir "pytest.txt"
    $xmlPath  = Join-Path $outDir "ket_qua.xml"
    $htmlPath = Join-Path $outDir "bao_cao.html"
    # v3.1: build each option as one quoted string; "--opt=(expr)" was split by
    # PowerShell and pytest received the path as a separate (missing) argument.
    & $py -m pytest tests -v --tb=short "--junitxml=$xmlPath" "--html=$htmlPath" --self-contained-html 2>&1 |
        ForEach-Object { $_.ToString() } | Tee-Object $log
    $code = $LASTEXITCODE
    $last = (Get-Content $log | Where-Object { $_ -match "(passed|failed|error|no tests ran)" } | Select-Object -Last 1)
    if ($code -eq 0) { Write-Host "pytest: DAT" -ForegroundColor Green; $summary.Add("pytest: DAT - $last") }
    else { Write-Host "pytest: CO LOI (exit $code)" -ForegroundColor Red; $summary.Add("pytest: LOI - $last"); $failed = $true }
}

# ------------------------------------------------------------ tom tat
$summary | Out-File (Join-Path $outDir "tom_tat.txt") -Encoding utf8
Write-Host "`n=== TOM TAT ===" -ForegroundColor Cyan
$summary | ForEach-Object { Write-Host $_ }
Write-Host "Ket qua da luu tai: $outDir"
if ($failed) { exit 1 } else { exit 0 }
