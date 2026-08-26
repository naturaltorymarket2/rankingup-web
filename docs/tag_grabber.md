# 상품 페이지 태그 수집 도구 (어드민용)

네이버가 서버에서의 자동 수집(스크래핑)을 차단하기 때문에,
어드민이 브라우저에서 직접 보고 있는 상품 페이지에서 태그를 뽑아낸다.

## 사용법

1. 어드민 화면에서 [상품 페이지 열기] → 네이버 상품 페이지가 열린다
2. 키보드 `F12` → 위쪽 탭에서 `Console` 클릭
3. (최초 1회) 입력창에 `allow pasting` 이라고 타이핑하고 Enter
4. 아래 스크립트 전체를 복사해 입력창에 붙여넣고 Enter
5. "태그 N개 복사됨" 이 뜨면 어드민 화면의 태그 입력창에 Ctrl+V

## 스크립트

```javascript
(()=>{const s=new Set(),o=[];
const push=t=>{t=(t||'').trim().replace(/^#+/,'');if(!t||t.length>30||/\s{2,}/.test(t))return;const k=t.replace(/\s/g,'').toLowerCase();if(k&&!s.has(k)){s.add(k);o.push(t);}};
document.querySelectorAll('a,span,li,em,strong').forEach(el=>{if(el.children.length)return;const t=el.textContent||'';if(/^#\S/.test(t.trim()))push(t);});
if(!o.length){const m=document.documentElement.innerHTML.match(/#[^\s"'<>#,]{1,30}/g)||[];m.forEach(push);}
const out=o.slice(0,10).map(t=>'#'+t).join('');
if(!out){alert('태그를 찾지 못했습니다. 페이지를 끝까지 스크롤한 뒤 다시 실행해 주세요.');return;}
navigator.clipboard.writeText(out).then(()=>alert('태그 '+o.slice(0,10).length+'개 복사됨\n\n'+out),
()=>prompt('아래 값을 직접 복사하세요 (Ctrl+C)',out));})();
```


---

## 더 간편한 방법 — 북마크(즐겨찾기) 등록

한 번만 등록해두면 상품 페이지에서 북마크 클릭만으로 태그가 복사된다.
F12 / allow pasting 과정이 필요 없다.

### 등록 방법 (최초 1회)

1. 크롬에서 `Ctrl + Shift + O` (북마크 관리자)
2. 오른쪽 빈 공간에 마우스 우클릭 → **새 북마크 추가**
3. 이름: `태그복사`
4. URL: `docs/tag_grabber_bookmarklet.txt` 파일의 내용 전체를 붙여넣기
5. 저장

### 사용 방법 (매 상품마다)

1. 어드민 화면 [상품 페이지 열기]
2. 상품명 아래 태그가 보이는 위치까지 스크롤
3. 북마크바에서 **태그복사** 클릭
4. "태그 N개 복사됨" 팝업 확인 → 어드민 태그 입력창에 Ctrl+V

※ 주소창에 직접 붙여넣으면 크롬이 javascript: 를 지우므로 반드시 북마크로 등록해야 한다.
