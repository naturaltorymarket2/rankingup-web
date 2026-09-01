# =============================================================
#  네이버 순위 수집 — 매일 오전 9시 자동 실행
#
#    1) naver_rank_standalone.py   순위 모니터링 서비스 (고객 상품)
#    2) reward_rank_crawler.py     리워드 광고 (메인/미션 키워드, 500위까지)
#
#  두 크롤러가 같은 디버그 포트로 크롬을 띄우므로 반드시 순차 실행한다.
#  실행 기록은 tools\logs\YYYY-MM-DD.log 에 남는다.
#
#  ※ .bat 대신 PowerShell 을 쓰는 이유
#     크롤러 경로에 한글이 들어 있는데(카카오톡 받은 파일),
#     cmd 는 UTF-8 배치 파일의 한글을 CP949 로 잘못 읽어 경로가 깨진다.
#     날짜 계산에 쓰던 wmic 도 최신 Windows 11 에서 제거됐다.
#
#  수동 실행:  powershell -ExecutionPolicy Bypass -File tools\run_daily_rank.ps1
# =============================================================

$ErrorActionPreference = 'Continue'

$Python     = 'C:\Python313\python.exe'
$RewardDir  = 'C:\Users\model\Desktop\quizcashnow'
$TrackerDir = Join-Path $env:USERPROFILE 'Documents\카카오톡 받은 파일\naver_rank_2026-08-21\naver_rank'
$LogDir     = Join-Path $RewardDir 'tools\logs'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }
$Log = Join-Path $LogDir ((Get-Date -Format 'yyyy-MM-dd') + '.log')

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $Log -Value $line -Encoding utf8
}

Write-Log '============================================================'
Write-Log '실행 시작'

# ── 사전 점검 ────────────────────────────────────────────────
$ok = $true
if (-not (Test-Path $Python))     { Write-Log "[오류] 파이썬을 찾을 수 없음: $Python"; $ok = $false }
if (-not (Test-Path $TrackerDir)) { Write-Log "[오류] 크롤러 폴더를 찾을 수 없음: $TrackerDir"; $ok = $false }
if (-not $ok) { Write-Log '사전 점검 실패 — 중단'; exit 1 }

# ── 1. 순위 모니터링 크롤러 ──────────────────────────────────
Write-Log '[1/2] 순위 모니터링 크롤러 시작'
Push-Location $TrackerDir
try {
    & $Python 'naver_rank_standalone.py' 2>&1 | ForEach-Object {
        Add-Content -Path $Log -Value $_ -Encoding utf8
    }
    Write-Log ("[1/2] 종료 코드: {0}" -f $LASTEXITCODE)
} catch {
    Write-Log ("[1/2] 예외: {0}" -f $_.Exception.Message)
} finally {
    Pop-Location
}

# 크롬이 완전히 닫히도록 대기.
# 두 크롤러는 같은 디버그 포트와 같은 네이버 계정을 쓴다. 겹쳐서 돌면
# 한 계정이 두 곳에서 동시에 검색하는 모양이 되어 차단된다.
# (2026-09-01 차단 발생 — 두 프로그램을 함께 실행한 것이 원인으로 추정)
Start-Sleep -Seconds 120

# ── 2. 리워드 광고 순위 크롤러 ───────────────────────────────
Write-Log '[2/2] 리워드 광고 크롤러 시작'
Push-Location $RewardDir
try {
    & $Python 'tools\reward_rank_crawler.py' 2>&1 | ForEach-Object {
        Add-Content -Path $Log -Value $_ -Encoding utf8
    }
    Write-Log ("[2/2] 종료 코드: {0}" -f $LASTEXITCODE)
} catch {
    Write-Log ("[2/2] 예외: {0}" -f $_.Exception.Message)
} finally {
    Pop-Location
}

Write-Log '실행 종료'
