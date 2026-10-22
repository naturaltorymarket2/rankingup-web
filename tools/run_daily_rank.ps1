# =============================================================
#  네이버 순위 수집 — 매일 오전 9시 자동 실행
#
#    1) naver_rank_standalone.py   순위 모니터링 서비스 (고객 상품)
#    2) reward_rank_crawler.py     리워드 광고 (메인/미션 키워드, 500위까지)
#    3) run_collect.ps1            SalesBrainAI 키워드 수집 (인사이트/수요/유입/지형/점수)
#    4) lookup_worker.py --refresh 판매수/유입 조회 '오늘 캐시' 선수집 (밤에도 즉시 응답)
#
#  셋 다 같은 디버그 포트와 네이버 계정으로 크롬을 띄우므로 반드시 순차 실행한다.
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

# 파이썬은 UTF-8 로 출력하는데 스케줄러가 띄운 콘솔 코드페이지는 cp949 라,
# 그냥 두면 크롤러가 이모지 한 글자에서 UnicodeEncodeError 로 즉사한다.
# (2026-09-29: naver_rank_standalone.py 가 시작 배너의 카트 이모지에서 죽어 순위 수집 통째로 누락)
$env:PYTHONUTF8       = '1'
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Python     = 'C:\Python313\python.exe'
$RewardDir  = 'C:\Users\model\Desktop\quizcashnow'
# 크롤러 폴더는 자주 옮겨진다(카카오톡 받은 파일 -> 바탕화면 등).
# 후보를 순서대로 확인해 실제로 존재하는 경로를 쓴다.
$TrackerCandidates = @(
    (Join-Path $env:USERPROFILE 'Desktop\naver_rank\naver_rank'),
    (Join-Path $env:USERPROFILE 'Desktop\naver_rank'),
    (Join-Path $env:USERPROFILE 'Documents\카카오톡 받은 파일\naver_rank_2026-08-21\naver_rank')
)
$TrackerDir = $TrackerCandidates[0]
foreach ($cand in $TrackerCandidates) {
    if (Test-Path (Join-Path $cand 'naver_rank_standalone.py')) { $TrackerDir = $cand; break }
}
$LogDir     = Join-Path $RewardDir 'tools\logs'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }
$Log = Join-Path $LogDir ((Get-Date -Format 'yyyy-MM-dd') + '.log')

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $Log -Value $line -Encoding utf8
}

# ── 네트워크(DNS) 준비 대기 ──────────────────────────────────
# PC 가 꺼져 있다 켜지면 작업 스케줄러가 바로 뜨는데, 그때는 와이파이·핫스팟이
# 아직 안 붙어 DNS 가 안 된다. 크롤러는 getaddrinfo 실패로 즉사하고 그날
# 수집이 통째로 빈다 (2026-10-20 실제 발생 — 10/20~10/22 사흘 공백).
# 파이썬 안의 3회 재시도(15초)로는 부팅 직후를 못 넘긴다.
#
# Supabase 도메인이 풀릴 때까지 최대 15분 기다렸다 시작한다.
function Wait-ForNetwork {
    param([int]$MaxMinutes = 15)

    $hosts    = @('wfxlihrqjtexuxvoajny.supabase.co', 'search.naver.com')
    $deadline = (Get-Date).AddMinutes($MaxMinutes)
    $waited   = $false

    while ((Get-Date) -lt $deadline) {
        $ok = $true
        foreach ($h in $hosts) {
            try {
                $null = [System.Net.Dns]::GetHostEntry($h)
            } catch {
                $ok = $false
                break
            }
        }
        if ($ok) {
            if ($waited) { Write-Log '[네트워크] 연결됨 - 수집을 시작합니다' }
            return $true
        }
        if (-not $waited) {
            Write-Log '[네트워크] DNS 가 아직 안 됩니다 - 최대 15분 기다립니다'
            $waited = $true
        }
        Start-Sleep -Seconds 30
    }

    Write-Log '[네트워크] 15분 동안 연결되지 않았습니다 - 오늘 수집을 건너뜁니다'
    return $false
}

if (-not (Wait-ForNetwork)) {
    Write-Log '수집 중단 (네트워크 없음)'
    exit 1
}

# ── 크롬 디버그 포트 정리 ────────────────────────────────────
# 앞 실행이 비정상 종료하면 크롬만 남아 포트를 계속 잡는다.
# 그러면 그 뒤로 매일 아무것도 수집하지 못한다(2026-09-25~26 이틀 공백).
# 실제로 크롤러가 도는지 파이썬 프로세스로 판별해, 남은 크롬이면 정리한다.
function Test-PortBusy {
    return [bool](Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue)
}

function Test-CrawlerRunning {
    $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -match 'naver_rank_standalone|reward_rank_crawler|collect_multi|keyword_demand|brand_inflow|keyword_public|score_hit_collector' }
    return ($procs | Measure-Object).Count -gt 0
}

function Clear-StaleChrome {
    param([string]$Step)

    if (-not (Test-PortBusy)) { return $true }

    $waited = 0
    while ((Test-PortBusy) -and (Test-CrawlerRunning) -and $waited -lt 1800) {
        Write-Log "[$Step] 다른 크롤러가 실행 중 - 60초 대기"
        Start-Sleep -Seconds 60
        $waited += 60
    }

    if (-not (Test-PortBusy)) { return $true }

    if (Test-CrawlerRunning) {
        Write-Log "[$Step] 30분을 기다렸지만 다른 크롤러가 계속 실행 중 - 건너뜀"
        return $false
    }

    Write-Log "[$Step] 남은 크롬이 포트를 잡고 있어 정리합니다"
    # 포트 9222(순위 크롤러)만 정리한다. 키퍼가 상시 소유하는 seller(9555)·coupang(9581)
    # 크롬은 절대 죽이지 않는다 — 죽이면 세션이 날아가고 '복원?' 블랭크 창이 뜬다(2026-10-08).
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*chrome_profile_*' `
            -and $_.CommandLine -notlike '*chrome_profile_seller*' `
            -and $_.CommandLine -notlike '*chrome_profile_coupang*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 5

    if (Test-PortBusy) {
        Write-Log "[$Step] 포트를 해제하지 못했습니다 - 건너뜀"
        return $false
    }
    return $true
}

Write-Log '============================================================'
Write-Log '실행 시작'

# ── 사전 점검 ────────────────────────────────────────────────
$ok = $true
if (-not (Test-Path $Python))     { Write-Log "[오류] 파이썬을 찾을 수 없음: $Python"; $ok = $false }
if (-not (Test-Path $TrackerDir)) { Write-Log "[오류] 크롤러 폴더를 찾을 수 없음: $TrackerDir"; $ok = $false }
if (-not $ok) { Write-Log '사전 점검 실패 — 중단'; exit 1 }

# ── 1. 순위 모니터링 크롤러 ──────────────────────────────────
if (-not (Clear-StaleChrome '1/3')) { Write-Log '[1/3] 건너뜀'; }
Write-Log '[1/3] 순위 모니터링 크롤러 시작'
Push-Location $TrackerDir
try {
    & $Python 'naver_rank_standalone.py' 2>&1 | ForEach-Object {
        Add-Content -Path $Log -Value $_ -Encoding utf8
    }
    Write-Log ("[1/3] 종료 코드: {0}" -f $LASTEXITCODE)
} catch {
    Write-Log ("[1/3] 예외: {0}" -f $_.Exception.Message)
} finally {
    Pop-Location
}

# 크롬이 완전히 닫히도록 대기.
# 두 크롤러는 같은 디버그 포트와 같은 네이버 계정을 쓴다. 겹쳐서 돌면
# 한 계정이 두 곳에서 동시에 검색하는 모양이 되어 차단된다.
# (2026-09-01 차단 발생 — 두 프로그램을 함께 실행한 것이 원인으로 추정)
Start-Sleep -Seconds 120

# ── 2. 리워드 광고 순위 크롤러 ───────────────────────────────
if (Clear-StaleChrome '2/3') {
    Write-Log '[2/3] 리워드 광고 크롤러 시작'
    Push-Location $RewardDir
    try {
        & $Python 'tools\reward_rank_crawler.py' 2>&1 | ForEach-Object {
            Add-Content -Path $Log -Value $_ -Encoding utf8
        }
        Write-Log ("[2/3] 종료 코드: {0}" -f $LASTEXITCODE)
    } catch {
        Write-Log ("[2/3] 예외: {0}" -f $_.Exception.Message)
    } finally {
        Pop-Location
    }
} else {
    # 앞 단계가 포트를 못 비웠다고 키워드 수집까지 버리지는 않는다.
    Write-Log '[2/3] 포트를 확보하지 못해 건너뜁니다'
}

# 크롬이 완전히 닫히도록 대기 (1->2 와 같은 이유: 같은 계정 동시 검색 = 차단)
Start-Sleep -Seconds 120

# -- 3. SalesBrainAI 키워드 수집 ------------------------------
# 별도 스케줄러 작업으로 따로 돌던 것을 여기로 합쳤다. 따로 돌면 순위 크롤러와
# 시간이 겹쳐 같은 계정이 두 곳에서 동시에 검색하는 모양이 되어 차단된다.
# run_collect.ps1 이 항목별 타임아웃/토스트/last_status.txt 를 스스로 처리하므로
# 여기서는 호출하고 종료 코드만 남긴다.
$CollectScript = Join-Path $TrackerDir 'run_collect.ps1'
if (-not (Test-Path $CollectScript)) {
    Write-Log "[3/3] 수집 스크립트를 찾을 수 없음: $CollectScript"
} elseif (-not (Clear-StaleChrome '3/3')) {
    Write-Log '[3/3] 포트를 확보하지 못해 건너뜁니다'
} else {
    Write-Log '[3/3] SalesBrainAI 키워드 수집 시작'
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CollectScript 2>&1 | ForEach-Object {
            Add-Content -Path $Log -Value $_ -Encoding utf8
        }
        Write-Log ("[3/3] 종료 코드: {0}" -f $LASTEXITCODE)
    } catch {
        Write-Log ("[3/3] 예외: {0}" -f $_.Exception.Message)
    }
}

# -- 4. 판매수/유입 조회 '오늘 캐시' 선수집 --------------------
# 고객이 밤에 눌러도 라이브 세션 없이 즉시 응답하도록, 그동안 조회된 적 있는 상품의
# 오늘 행을 미리 채운다. 대부분 쿠키/http 경로라 순위 크롤러(9222)와 포트가 겹치지
# 않는다 — 셀러 세션(9581, 키퍼가 상시 소유)만 쓰므로 Clear-StaleChrome 불필요.
# 건수가 늘 수 있어 lookup_worker 내부에서 시간을 끊어(paced) 돈다.
Write-Log '[4/4] 조회 캐시 선수집 시작 (lookup_worker --refresh)'
Push-Location $TrackerDir
try {
    & $Python 'lookup_worker.py' '--refresh' 2>&1 | ForEach-Object {
        Add-Content -Path $Log -Value $_ -Encoding utf8
    }
    Write-Log ("[4/4] 종료 코드: {0}" -f $LASTEXITCODE)
} catch {
    Write-Log ("[4/4] 예외: {0}" -f $_.Exception.Message)
} finally {
    Pop-Location
}

Write-Log '실행 종료'
