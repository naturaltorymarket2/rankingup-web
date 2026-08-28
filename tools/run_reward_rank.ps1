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

$ErrorActionPreference = 'Continue'

$Python    = 'C:\Python313\python.exe'
$RewardDir = 'C:\Users\model\Desktop\quizcashnow'
$LogDir    = Join-Path $RewardDir 'tools\logs'

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

# 순위 모니터링 크롤러가 아직 돌고 있으면 크롬 디버그 포트(9222)가 충돌한다.
# 포트가 열려 있으면 앞 작업이 끝날 때까지 최대 30분 기다린다.
$waited = 0
while ($waited -lt 1800) {
    $busy = Test-NetConnection -ComputerName '127.0.0.1' -Port 9222 -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $busy) { break }
    Write-Log '앞선 크롤러가 아직 실행 중 (포트 9222 사용) - 60초 대기'
    Start-Sleep -Seconds 60
    $waited += 60
}

Push-Location $RewardDir
try {
    & $Python 'tools\reward_rank_crawler.py' 2>&1 | ForEach-Object {
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
