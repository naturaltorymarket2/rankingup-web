# =============================================================
#  리워드 광고 순위 수집 — 매일 오전 9시 30분 자동 실행
#
#  승인 완료된 광고의 메인(시드) 키워드와 각 미션 키워드로
#  네이버 쇼핑을 500위까지 훑어 campaign_rank_history 에 기록한다.
#
#  ※ 순위 모니터링 서비스(naver_rank_standalone)는 기존 작업
#    "NaverRank_Daily" 가 담당한다. 이 스크립트는 리워드 광고만 처리한다.
#    두 크롤러가 같은 크롬 디버그 포트를 쓰므로 시간을 겹치지 않게 둔다.
#      08:00~09:00  NaverRank_Daily      (순위 모니터링)
#      09:30        이 스크립트          (리워드 광고)
#
#  수동 실행:
#    powershell -ExecutionPolicy Bypass -File tools\run_reward_rank.ps1
# =============================================================

# -Refresh : 건너뛰기 규칙(7일 주기·500위 밖·오늘 수집분·1회 20개)을
#            무시하고 전부 다시 수집한다. 앱의 상품 위치 힌트를
#            지금 맞춰야 할 때 쓴다.
param([switch]$Refresh)

$ErrorActionPreference = 'Continue'

$Python    = 'C:\Python313\python.exe'
$RewardDir = 'C:\Users\model\Desktop\quizcashnow'
$LogDir    = Join-Path $RewardDir 'tools\logs'

# 파이썬 출력 인코딩 고정 (재사용 크롤러가 이모지를 출력한다)
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }
$Log = Join-Path $LogDir ((Get-Date -Format 'yyyy-MM-dd') + '.log')

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $Log -Value $line -Encoding utf8
}

Write-Log '============================================================'
Write-Log '리워드 광고 순위 수집 시작'

if (-not (Test-Path $Python)) {
    Write-Log "[오류] 파이썬을 찾을 수 없음: $Python"
    exit 1
}

# 순위 모니터링 크롤러와 같은 크롬 디버그 포트(9222)를 쓴다.
#
# 문제가 됐던 것: 앞 작업이 비정상 종료하면 크롬만 남아 포트를 계속 잡는다.
# 그러면 다음 날부터 매일 '포트 사용 중'으로 아무것도 수집하지 못한다
# (2026-09-25 ~ 09-26 이틀간 이렇게 비었다).
#
# 그래서 '실제로 크롤러가 돌고 있는지'를 파이썬 프로세스로 판별한다.
#   - 돌고 있으면      : 끝날 때까지 최대 30분 기다린다
#   - 남은 크롬뿐이면  : 정리하고 진행한다
function Test-PortBusy {
    $c = Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue
    return [bool]$c
}

function Test-CrawlerRunning {
    $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -match 'naver_rank_standalone|reward_rank_crawler' }
    return ($procs | Measure-Object).Count -gt 0
}

$waited = 0
while ((Test-PortBusy) -and (Test-CrawlerRunning) -and $waited -lt 1800) {
    Write-Log '앞선 크롤러가 실행 중 (포트 9222 사용) - 60초 대기'
    Start-Sleep -Seconds 60
    $waited += 60
}

if (Test-PortBusy) {
    if (Test-CrawlerRunning) {
        Write-Log '[중단] 30분을 기다렸지만 앞선 크롤러가 계속 실행 중입니다.'
        exit 1
    }

    # 크롤러는 없는데 포트만 잡혀 있다 = 지난 실행에서 남은 크롬
    Write-Log '남은 크롬이 포트를 잡고 있어 정리합니다 (크롤러 전용 프로필만 종료)'
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*chrome_profile_*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 5

    if (Test-PortBusy) {
        Write-Log '[중단] 포트를 해제하지 못했습니다. 크롬을 모두 닫고 다시 실행하세요.'
        exit 1
    }
    Write-Log '정리 완료 - 수집을 계속합니다'
}

Push-Location $RewardDir
try {
    $crawlerArgs = @('tools\reward_rank_crawler.py')
    if ($Refresh) {
        $crawlerArgs += '--refresh'
        Write-Log '전체 갱신 모드로 실행합니다'
    }

    & $Python $crawlerArgs 2>&1 | ForEach-Object {
        Add-Content -Path $Log -Value $_ -Encoding utf8
        Write-Host $_
    }
    Write-Log ("종료 코드: {0}" -f $LASTEXITCODE)
} catch {
    Write-Log ("예외: {0}" -f $_.Exception.Message)
} finally {
    Pop-Location
}

Write-Log '리워드 광고 순위 수집 종료'
