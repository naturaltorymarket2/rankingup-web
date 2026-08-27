@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM  네이버 순위 수집 — 매일 오전 9시 자동 실행
REM
REM   1) naver_rank_standalone.py   순위 모니터링 서비스 (고객 상품)
REM   2) reward_rank_crawler.py     리워드 광고 (메인 키워드, 500위까지)
REM
REM  두 크롤러가 같은 디버그 포트로 크롬을 띄우므로 반드시 순차 실행한다.
REM  실행 기록은 tools\logs\ 아래 날짜별로 남는다.
REM ============================================================

set PYTHON=C:\Python313\python.exe
set REWARD_DIR=C:\Users\model\Desktop\quizcashnow
set TRACKER_DIR=C:\Users\model\Documents\카카오톡 받은 파일\naver_rank_2026-08-21\naver_rank
set LOG_DIR=%REWARD_DIR%\tools\logs

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM 로그 파일명: 2026-08-27.log (날짜 형식이 달라도 동작하도록 WMIC 사용)
for /f %%i in ('wmic os get localdatetime ^| find "."') do set DT=%%i
set TODAY=%DT:~0,4%-%DT:~4,2%-%DT:~6,2%
set LOG=%LOG_DIR%\%TODAY%.log

echo. >> "%LOG%"
echo ============================================================ >> "%LOG%"
echo  실행 시작: %date% %time% >> "%LOG%"
echo ============================================================ >> "%LOG%"

REM ── 1. 순위 모니터링 크롤러 ─────────────────────────────────
echo [1/2] 순위 모니터링 크롤러 시작... >> "%LOG%"
cd /d "%TRACKER_DIR%"
"%PYTHON%" naver_rank_standalone.py >> "%LOG%" 2>&1
echo [1/2] 종료 코드: %ERRORLEVEL% >> "%LOG%"

REM 크롬이 완전히 닫히도록 잠시 대기 (두 크롤러가 같은 포트를 쓴다)
timeout /t 15 /nobreak > nul

REM ── 2. 리워드 광고 순위 크롤러 ──────────────────────────────
echo [2/2] 리워드 광고 크롤러 시작... >> "%LOG%"
cd /d "%REWARD_DIR%"
"%PYTHON%" tools\reward_rank_crawler.py >> "%LOG%" 2>&1
echo [2/2] 종료 코드: %ERRORLEVEL% >> "%LOG%"

echo  실행 종료: %date% %time% >> "%LOG%"

endlocal
