"""
리워드 광고 순위 크롤러 — 매일 1회 실행

무엇을 하나:
    승인 완료된 광고의 **메인(시드) 키워드**로 네이버 쇼핑 검색을 훑어
    최대 500위까지 상품 순위를 찾아 campaign_rank_history 에 기록한다.
    500위 안에 없으면 rank = NULL 로 기록한다 (화면에는 '500위 밖'으로 표시).

왜 크롤링인가:
    - 네이버 공식 쇼핑 검색 API는 2026년 종료(404)됐다.
    - SerpApi 통합검색은 10위까지만 보여 순위 추이 기록에 쓸 수 없고,
      매일 호출하면 쿼터도 감당이 안 된다.
    → 순위 추적 서비스에서 이미 쓰고 있는 크롤러(naver_rank_standalone.py)를
      그대로 재사용한다. 로그인된 실제 크롬에 붙는 방식이라 차단을 피한다.

실행 (매일 아침, naver_rank_standalone 돌릴 때 함께):
    python tools/reward_rank_crawler.py
    python tools/reward_rank_crawler.py --test     # 첫 1건만 확인

사전 준비:
    1) .env 에 SUPABASE_URL / SUPABASE_SECRET_KEY 설정 (이미 되어 있음)
    2) 크롤러 경로 지정 — 기본값이 다르면 환경변수로 지정한다
       set NRS_PATH=C:\\경로\\naver_rank_standalone.py
    3) playwright 설치 (순위 추적 크롤러와 동일 환경이면 이미 설치됨)
"""

import os
import sys
import time
import random
import argparse
import importlib.util
from pathlib import Path
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict, Any

import requests

# ─────────────────────────────────────────────────────────────────────────────
# 설정
# ─────────────────────────────────────────────────────────────────────────────

BASE_DIR = Path(__file__).resolve().parent.parent

# 최대 탐색 순위 — 이 순위까지 못 찾으면 '500위 밖'으로 기록하고 더 훑지 않는다
MAX_RANK = 500

# 상품 간 대기 (초) — 연속 요청으로 차단되지 않도록
DELAY_BETWEEN = (4, 8)

# 순위 추적 서비스의 크롤러 위치 (로그인/차단감지/페이지네이션 로직 재사용)
DEFAULT_NRS_PATH = Path(
    os.path.expanduser('~/Documents/카카오톡 받은 파일/naver_rank_2026-08-21/'
                       'naver_rank/naver_rank_standalone.py')
)

KST = timezone(timedelta(hours=9))


def load_env() -> Dict[str, str]:
    """.env 파일에서 Supabase 접속 정보를 읽는다"""
    env: Dict[str, str] = {}
    env_path = BASE_DIR / '.env'
    if env_path.exists():
        for line in env_path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip()

    url = env.get('SUPABASE_URL') or os.getenv('SUPABASE_URL', '')
    key = (env.get('SUPABASE_SECRET_KEY')
           or env.get('SUPABASE_SERVICE_ROLE_KEY')
           or os.getenv('SUPABASE_SECRET_KEY', ''))
    if not url or not key:
        sys.exit('.env 에 SUPABASE_URL / SUPABASE_SECRET_KEY 가 필요합니다')
    return {'url': url, 'key': key}


def load_crawler():
    """naver_rank_standalone.py 를 모듈로 불러온다 (실행은 하지 않음)"""
    path = Path(os.getenv('NRS_PATH', str(DEFAULT_NRS_PATH)))
    if not path.exists():
        sys.exit(
            f'크롤러를 찾을 수 없습니다: {path}\n'
            f'환경변수 NRS_PATH 로 naver_rank_standalone.py 경로를 지정하세요.'
        )
    spec = importlib.util.spec_from_file_location('nrs', path)
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(path.parent))   # 같은 폴더의 보조 모듈 import 대비
    spec.loader.exec_module(module)
    print(f'크롤러 로드: {path}')
    return module


# ─────────────────────────────────────────────────────────────────────────────
# Supabase
# ─────────────────────────────────────────────────────────────────────────────

def sb_headers(env: Dict[str, str]) -> Dict[str, str]:
    return {
        'apikey':        env['key'],
        'Authorization': 'Bearer ' + env['key'],
        'Content-Type':  'application/json',
    }


def load_targets(env: Dict[str, str]) -> List[Dict[str, Any]]:
    """
    승인 완료 + 진행 중인 광고를 그룹 단위로 모은다.

    같은 (상품URL, 메인키워드) 조합은 한 번만 크롤링하고,
    결과는 그룹 내 모든 캠페인에 동일하게 기록한다.
    """
    res = requests.get(
        env['url'] + '/rest/v1/campaigns',
        headers=sb_headers(env),
        params={
            'select': 'id,group_id,product_url,keyword,seed_keyword,'
                      'product_name,brand_name,expires_at',
            'status':          'eq.ACTIVE',
            'approval_status': 'eq.APPROVED',
        },
        timeout=30,
    )
    res.raise_for_status()
    rows = res.json()

    now = datetime.now(timezone.utc)
    groups: Dict[tuple, Dict[str, Any]] = {}

    # 그룹별 대표 캠페인 (시드 순위를 기록할 대상 — 대시보드 차트 기준)
    representative: Dict[str, str] = {}
    for row in sorted(rows, key=lambda r: r.get('id') or ''):
        gid = row.get('group_id')
        if gid and gid not in representative:
            representative[gid] = row['id']

    def add_target(product_url, keyword, row, campaign_id, is_seed):
        key = (product_url, keyword, is_seed)
        if key not in groups:
            groups[key] = {
                'product_url':  product_url,
                'keyword':      keyword,
                'product_name': row.get('product_name') or '',
                'brand_name':   row.get('brand_name') or '',
                'is_seed':      is_seed,
                'campaign_ids': [],
            }
        if campaign_id not in groups[key]['campaign_ids']:
            groups[key]['campaign_ids'].append(campaign_id)

    for row in rows:
        # 기간이 끝난 광고는 추적하지 않는다
        expires = row.get('expires_at')
        if expires:
            try:
                if datetime.fromisoformat(expires.replace('Z', '+00:00')) < now:
                    continue
            except ValueError:
                pass

        url = row['product_url']

        # ① 미션 키워드 순위 — 앱 화면의 "몇 위쯤에 있어요" 힌트에 쓰인다
        mission_kw = (row.get('keyword') or '').strip()
        if mission_kw:
            add_target(url, mission_kw, row, row['id'], False)

        # ② 시드(순위 추적 대표) 키워드 순위 — 광고주 대시보드 차트 기준
        seed_kw = (row.get('seed_keyword') or '').strip()
        gid     = row.get('group_id')
        if seed_kw and gid and representative.get(gid) == row['id']:
            add_target(url, seed_kw, row, row['id'], True)

    return list(groups.values())


def save_rank(env: Dict[str, str], campaign_ids: List[str],
              rank: Optional[int], checked_to: int,
              keyword: str = '', is_seed: bool = True) -> None:
    """
    당일 기록이 있으면 UPDATE, 없으면 INSERT (하루 1건 유지).
    rank=None 은 '500위 밖'을 의미한다.
    """
    day_start = datetime.now(KST).replace(hour=0, minute=0, second=0, microsecond=0)
    day_end   = day_start + timedelta(days=1)
    now_utc   = datetime.now(timezone.utc).isoformat()

    for campaign_id in campaign_ids:
        # 같은 날 + 같은 키워드 기록이 있으면 갱신, 없으면 새로 넣는다
        existing = requests.get(
            env['url'] + '/rest/v1/campaign_rank_history',
            headers=sb_headers(env),
            params={
                'select':      'id',
                'campaign_id': 'eq.' + campaign_id,
                'is_seed':     'is.' + ('true' if is_seed else 'false'),
                'checked_at':  'gte.' + day_start.isoformat(),
                'limit':       '1',
            },
            timeout=30,
        )
        existing.raise_for_status()
        rows = existing.json()

        payload = {
            'rank':       rank,
            'checked_at': now_utc,
            'checked_to': checked_to,
            'keyword':    keyword,
            'is_seed':    is_seed,
        }

        if rows:
            requests.patch(
                env['url'] + '/rest/v1/campaign_rank_history',
                headers=sb_headers(env),
                params={'id': 'eq.' + rows[0]['id']},
                json=payload,
                timeout=30,
            ).raise_for_status()
        else:
            payload['campaign_id'] = campaign_id
            requests.post(
                env['url'] + '/rest/v1/campaign_rank_history',
                headers=sb_headers(env),
                json=payload,
                timeout=30,
            ).raise_for_status()

    _ = day_end  # (범위 계산 의도를 남기기 위한 참조)


# ─────────────────────────────────────────────────────────────────────────────
# 크롤링
# ─────────────────────────────────────────────────────────────────────────────

def to_product(target: Dict[str, Any], nrs) -> Dict[str, Any]:
    """크롤러의 check_rank(page, product) 가 기대하는 형태로 변환"""
    url = target['product_url']

    # 스마트스토어/브랜드스토어 URL 마지막 숫자 = 네이버 상품 ID(mallProductId)
    product_id = ''
    for part in reversed(url.split('?')[0].rstrip('/').split('/')):
        if part.isdigit():
            product_id = part
            break

    # smartstore.naver.com/{store_slug}/products/... 에서 스토어 식별자 추출
    store_slug = ''
    parts = url.split('//')[-1].split('/')
    if len(parts) > 1 and 'naver.com' in parts[0]:
        store_slug = parts[1]

    return {
        'id':                target['campaign_ids'][0],
        'name':              target['product_name'],
        'url':               url,
        'naver_product_id':  product_id,
        'store_slug':        store_slug,
        'keyword':           target['keyword'],
        'max_rank':          MAX_RANK,
    }


def main(test_mode: bool = False) -> None:
    env = load_env()
    nrs = load_crawler()

    targets = load_targets(env)
    if test_mode:
        targets = targets[:1]

    print(f'\n대상 광고: {len(targets)}건 (최대 {MAX_RANK}위까지 확인)\n')
    if not targets:
        return

    account = nrs.NAVER_ACCOUNTS[random.randrange(len(nrs.NAVER_ACCOUNTS))]
    port    = nrs.CDP_PORT_BASE
    profile = Path(nrs.BASE_DIR) / ('chrome_profile_' + account['id'])

    proc = nrs.launch_chrome(profile, port)
    success = outside = failed = 0

    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser = p.chromium.connect_over_cdp('http://localhost:%d' % port)
            context = browser.contexts[0] if browser.contexts else browser.new_context()
            page    = context.pages[0] if context.pages else context.new_page()

            if not nrs.ensure_login(context, page, account):
                sys.exit('네이버 로그인 실패 — naver_rank_standalone.py --warmup 으로 먼저 로그인하세요')

            for i, target in enumerate(targets, 1):
                product = to_product(target, nrs)
                kind = '시드' if target.get('is_seed') else '미션'
                print(f'[{i}/{len(targets)}] [{kind}] "{product["keyword"]}" '
                      f'— {product["name"][:30]}')

                result = nrs.check_rank(page, product)

                if result.get('blocked'):
                    print(f'    ⚠️ 차단 감지: {result.get("blocked")} — 중단합니다')
                    failed += 1
                    break

                rank       = result.get('rank')
                checked_to = result.get('checked_to') or 0

                save_rank(env, target['campaign_ids'], rank, checked_to,
                          keyword=target['keyword'],
                          is_seed=target.get('is_seed', True))

                if rank:
                    print(f'    → {rank}위 (캠페인 {len(target["campaign_ids"])}개 기록)')
                    success += 1
                else:
                    print(f'    → {MAX_RANK}위 밖 ({checked_to}위까지 확인)')
                    outside += 1

                if i < len(targets):
                    time.sleep(random.uniform(*DELAY_BETWEEN))

            browser.close()
    finally:
        nrs.stop_chrome(proc)

    print(f'\n완료 — 순위 확인 {success}건 / {MAX_RANK}위 밖 {outside}건 / 실패 {failed}건')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='리워드 광고 순위 크롤러')
    parser.add_argument('--test', action='store_true', help='첫 1건만 확인')
    args = parser.parse_args()
    main(test_mode=args.test)
