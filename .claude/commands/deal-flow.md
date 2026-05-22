---
description: 주간 Monday Brief용 자본시장 동향 + 주요 거래 동향 큐레이션 (각 10개 후보 → 사용자 선택 → MD 파일 저장)
---

# Weekly Deal Flow — Monday Brief Section Curation **v2** (news-clipping 기준 동기화)

매주 금요일 16:00 KST 루틴. **Monday Morning Brief**의 *Page 5: 자본시장 동향* + *Page 6: 주요 거래 동향* 섹션을 채울 기사를 큐레이션해 대시보드 `/#deals` 페이지에 주차별로 적재한다.

> **실행 위치**: 리포 루트에서 Claude Code를 실행해야 한다. CWD = `reverent-dashboard/`. `./deals/`, `./news/` 상대 경로로 동작.

**3단계 워크플로우** (v2 — Phase 0 신설):
- **Phase 0**: 그 주의 일일 news-clipping(`./news/{Mon~Fri}.md`)에서 *Deal / 자본시장 동향* 섹션 추출 → 주간 누적 신호 맵 구축
- **Phase 1**: 1차 매체 fetch + 페이지네이션 + Phase 0 신호 → 각 페이지 10건 후보 카드 (scoring rubric 적용) → 사용자 선택 요청
- **Phase 2**: 사용자 선택 응답 → 최종 MD 본문 + Valuation 블록 + `./deals/{endDate}.md` 저장 + `./deals/index.json` 갱신

## 기준 날짜와 기간

- **endDate**: 명령 실행 시각(KST) 기준 그 주의 금요일 (월~목에 실행 시 다가오는 금요일, 토~일에 실행 시 직전 금요일)
- **startDate**: endDate − 4일 (월요일)
- **파일명**: `./deals/{endDate}.md` (예: `./deals/2026-05-15.md`)
- **헤더 표기**: `2026-05-11 ~ 2026-05-15`

---

## Phase 0: 일일 news-clipping 주간 누적 신호 추출 (신규)

그 주의 일일 클리핑 파일을 모두 Read → Deal/자본시장 동향 섹터의 헤드라인·핵심 키워드를 수집 → 주간 누적 신호 맵 구축.

### Step 0-1) 파일 읽기
```
Read  ./news/{startDate}.md    (월요일)
Read  ./news/{startDate+1}.md  (화요일)
Read  ./news/{startDate+2}.md  (수요일)
Read  ./news/{startDate+3}.md  (목요일)
Read  ./news/{endDate}.md      (금요일)
```
존재하는 파일만 처리. 누락 일자 있으면 skip하고 진행. (예: 명령 실행이 화요일이면 월·화만 존재 → 두 파일만 읽음)

### Step 0-2) 섹션 추출
각 파일에서 `## 6. Deal / 자본시장 동향` (또는 `## 6.` 으로 시작하는 마지막 섹터) 의 헤드라인·당사자(기업명)·거래 단계·핵심 숫자를 추출.

### Step 0-3) 누적 신호 맵 구축
```
{
  "<deal slug>": {
    "headline": "원본 헤드라인",
    "parties": ["회사 A", "PEF B"],
    "count": 3,                          // 그 주 등장 횟수
    "dates": ["2026-05-12", "2026-05-13"],
    "sources": ["thebell", "dealsite"],
    "stage_progression": ["매각 검토", "우협 선정"]  // 단계 진전 있었나
  },
  ...
}
```

이 맵은 Phase 1의 scoring에서 **weekly_signal_count** 차원으로 직접 반영. 또 **단계 진전**이 있는 사안(예: 월 "매각 검토" → 목 "우협 선정")은 가중 부스트.

---

## Phase 1: 후보 카드 생성 — scoring rubric 적용

### Step 1-1) 1차 매체 fetch (병렬, news-clipping과 동일)
```
WebFetch  https://www.thebell.co.kr/front/NewsList.asp?Code=0103   (M&A·IPO·PE — 페이지 1~3)
WebFetch  https://dealsite.co.kr/categories/080000                   (M&A — 페이지 1~3)
WebFetch  https://dealsite.co.kr/categories/075000                   (PEF·VC·대체투자 — 페이지 1~3)
WebFetch  https://www.investchosun.com/                              (PEF·M&A 1차)
```
페이지네이션 2~3페이지까지 (news-clipping 정책과 동기화).

### Step 1-2) 1순위 PE/LP·자문사·기업 점검 (news-clipping 1순위 동기화)

다음 매주 의무 검색 대상 — 24h 내 또는 그 주 보도 있는지 직접 확인:

**🥇 글로벌 메가 PE**: Bain Capital · KKR · Blackstone · Carlyle · Apollo · Brookfield · TPG · Macquarie PE · Affinity Equity Partners

**🥇 국내 PEF**: MBK Partners · IMM PE · Hahn & Co · 어피니티 · 캑터스PE · UCK파트너스 · 원익투자파트너스 · 오로라파트너스 · 스카이레이크 · 에이티넘 · 센트로이드PE · 메리츠PE · 다올PE · 베인크레딧 · 카무르PE · JKL파트너스

**🥇 국내 VC**: 스틱벤처스 · 서울투자파트너스 · 한국성장금융 · 한국벤처투자 · 우리벤처 · 하나에스앤비인베

**🥇 정책기관·LP**: 국민성장펀드 · 모태펀드 · KDB산업은행 · IBK기업은행 · 신한자산운용 · 새마을금고 · 총회연금재단 · 예금보험공사 · 금감원 · 금융위 · 거래소

**🥇 빅딜 추적 대상** (이미 진행 중인 잠재 빅딜): KAI 지분 매입(한화) · 카리플렉스 매각 · 율곡 인수전 · 만전식품 · KDB생명 · 예별손해보험 · 코오롱인더 스페셜티 · SK TNS · 시아스 · 이투마스

### Step 1-3) 후보 카테고리 분류

#### Page 5 — 자본시장 동향 (정책·시장 구조·펀드 결성·IB 동향)
- 🅐 **정책/규제**: 금융위·한은·거래소·국세청 정책 변화 (자본시장법, ETF 규제, RWA 완화 등)
- 🅑 **펀드결성·GP선정**: 국민성장펀드 자펀드, 블라인드펀드 결성, 정책자금 위탁운용사 선정
- 🅒 **IPO 시장**: 개별 종목 X, 시장 동향·제도 변화 O (코스닥 리그 개편 등)
- 🅓 **시장구조·IB 동향**: 인수금융 시장, 증권사 IB 채용·조직, RWA·자본규제
- 🅔 **통화·환율·금리**: 한은 금통위, 연준, 외환 정책

#### Page 6 — 주요 거래 동향 (개별 거래·진행 단계)
- 🅐 **PE Buyout**: 사모펀드 경영권 인수
- 🅑 **기업간 인수**: 전략적 SI 인수 (수직계열화·볼트온)
- 🅒 **매각 추진**: 매각자문 선정·티저레터·예비입찰
- 🅓 **우협 선정**: 우협 발표
- 🅔 **SPA 체결**: 본계약 체결·딜클로징
- 🅕 **Pre-IPO/VC 투자**: 그로스·시리즈 라운드
- 🅖 **리파이낸싱**: PEF 인수금융 리파이낸싱·세컨더리

### Step 1-4) Scoring rubric (정교화)

각 후보에 **0~10 score** 부여. 가중평균으로 산출.

#### Page 5 score 공식
```
score = 0.30 × policy_impact      # 자본시장 전반 영향력
      + 0.25 × weekly_signal      # Phase 0 누적 신호 (count×3, max 10)
      + 0.20 × concreteness       # 정량 정보·일자·당사자 명시도
      + 0.15 × source_diversity   # 매체 cross-ref 개수 (1→4, 2→7, 3+→10)
      + 0.10 × timeliness         # 주 후반 임팩트 (Fri→10, Mon→6, 이전 주→3)
```

**policy_impact 척도**:
- 10: 정책 패러다임 변화 (국민성장펀드, RWA 완화 등)
- 7: 새 펀드 결성·GP 선정·금융사 매각 본격화
- 5: 증권사 개별 조직 개편·IB 채용 동향
- 3: 단발성 인사·간행물

#### Page 6 score 공식
```
score = 0.30 × deal_stage         # SPA > 본입찰 > 예비입찰 > 매각 검토
      + 0.20 × valuation_coverage # EV/EBITDA·매출·EBITDA 공개 정도
      + 0.15 × deal_size          # 조 단위>천억 단위>백억 단위
      + 0.15 × weekly_signal      # Phase 0 누적 신호 + 단계 진전 부스트
      + 0.10 × source_diversity   # 매체 cross-ref
      + 0.10 × strategic_signal   # K-방산·K-푸드·AI 같은 산업 트렌드 연결
```

**deal_stage 척도**:
- 10: SPA 체결·딜 클로징
- 8: 우협 확정·본입찰 마감
- 6: 예비입찰·매각자문 선정
- 4: 매각 검토·관심 표명
- 2: 루머·이름만 거론

**valuation_coverage 척도**:
- 10: EV/EBITDA·매출·EBITDA 모두 공개
- 7: Deal Value + 지분율 + 일부 정량
- 4: Deal Value 추정만
- 1: 모두 비공개

**deal_size 척도**:
- 10: 1조원 이상
- 8: 5,000억~1조
- 6: 1,000~5,000억
- 4: 500~1,000억
- 2: 500억 미만 또는 미공개

**weekly_signal** (공통):
- count 0 → 1점 (이번 주 신규)
- count 1 → 4점
- count 2 → 7점
- count 3+ → 10점
- + 단계 진전 있으면 +2점 부스트 (max 10 cap)

### Step 1-5) 필수 필드 (각 후보)

```json
{
  "rank": 1,
  "title": "보도자료 헤드라인 (60자 이내)",
  "date": "YYYY.MM.DD",
  "category": "🅑 펀드결성·GP선정",
  "score": 9.2,
  "score_breakdown": "정책 9 / 주간신호 ×3 / 정량 9 / 매체 3개 / 신선도 10",
  "bullets": ["~함", "~임", "~예상"],
  "weekly_signal_count": 3,
  "stage_progression": "매각 검토 → 우협 선정",   // Phase 0 추적 (Page 6 한정)
  "financials": "거래 1,750억 / 지분 70% / EV/EBITDA n/a",  // Page 6 한정 — valuation 의무
  "source": "더벨",
  "url": "원문 URL"
}
```

### Step 1-6) bullets 작성 규칙

**공통**:
- 거래 규모·기업가치·멀티플·지분율 등 **정량 정보 우선**
- 굵게 강조는 `**bold**` 사용
- 한 bullet에 여러 데이터 포인트 압축
- 톤: `~함`, `~임`, `~예상`, `~전망` 명사형 종결 (음슴체)
- 마지막 bullet은 시사점·변수·전망

**Page 6 추가 — Valuation 의무 포함** (news-clipping 동기화):
모든 거래 요약에 다음을 명시 (비공개면 "비공개"로 표기):
- 거래 규모 (₩X조, $X B 등 절대값)
- 지분율 (51%, 70.6%, 80:20 컨소시엄 등)
- 밸류에이션 배수 (EV/EBITDA, PER, EV/Sales)
- 펀드 약정총액 (블라인드 PEF·정책펀드 규모)
- 자금조달 구조 (인수금융 주선사, 메자닌, TRS, 콜옵션, 언아웃, secondary)
- 자문사 (매각자문·인수자문)

---

## ⛔ Hard Rules — news-clipping과 동기화

### URL 날짜 메커니컬 검증
출처 URL path의 날짜 패턴을 먼저 체크. **그 주 월~금 + 이전 주말 (총 7일)** 을 벗어나면 본문 확인 없이 폐기.

| 매체 | URL 패턴 | 예 |
|---|---|---|
| thebell.co.kr | `key=YYYYMMDD…` | `key=202605111538` → 5/11 |
| dealsite.co.kr | `/articles/{id}/...` (날짜 미포함) | 본문 확인 필수 |
| investchosun.com | `/YYYY/MM/DD/YYYYMMDD…` | `/2026/05/04/2026050480136` → 5/4 |
| hankyung.com | `/article/YYYYMMDD####` | `2026051574301` → 5/15 |
| etnews.com | `/YYYYMMDD######` | `20260512000037` → 5/12 |
| sedaily.com | `/.../YYYY/MM/DD/` | `2026/05/12/` → 5/12 |

### 본문 timestamp 2차 검증
URL 날짜 없는 매체(dealsite 등) 또는 보강 필요 시:
- 본문 상하단의 게재 일자·시각 명시적 확인
- "오늘자", "방금 전" 같은 모호한 표현으로 끼우지 말 것

### 출처 URL과 본문 내용 일치
각 후보의 source URL을 클릭했을 때 동일 주제 기사가 나와야 함. 동일 사안 다른 보도 매핑 금지.

### 매체 다양성
- 같은 매체가 한 페이지(Page 5 또는 6) 안에서 **3건 이상 연속 등장 금지**
- thebell·dealsite·인베스트조선·한국경제·서울경제 등 다양화
- 단일 매체 의존도 50% 이하

### 텔레그램·증권사 데스크 언급 금지 (news-clipping과 동기화)
출처는 무조건 신뢰 언론 매체명만. "하나증권 ~ 텔레그램", "메리츠 데스크", "@HI_GS", "텔레그램에서 재조명" 등 표현 본문·source·implication 어디에도 금지.

---

## Step 1-7) 채팅 출력 형식 (refined)

```markdown
# 📋 Weekly Deal Flow 후보 — 2026-05-11 ~ 2026-05-15
> Phase 0 누적 신호: 일일 클리핑 5건 중 4건 처리 (5/12 누락), Deal 섹터 23건 추출

## 1. 자본시장 동향 후보 (10건)

### [1] 헤드라인 (2026.05.12) · *🅑 펀드결성·GP선정* · score 9.4 (📊 ×3, 📈 단계진전)
- bullet 1
- bullet 2
- bullet 3
- ※ 출처: 더벨 · [원문](url)
- ※ Phase 0: 5/12·5/13·5/14 일일 클리핑 등장 (count: 3) — "예비입찰 → 우협 선정" 단계 진전

### [2] ...
(10건 반복)

## 2. 주요 거래 동향 후보 (10건)

### [1] 헤드라인 (2026.05.11) · *🅐 PE Buyout* · score 9.7 (💰 ₩1조+ · 📊 ×2)
- bullet 1
- bullet 2
- bullet 3
- ※ Valuation: 거래 1조원 / 지분 100% / EV/EBITDA 비공개 / 자문 미래에셋
- ※ 출처: 인베스트조선 · [원문](url)
- ※ Phase 0: 5/11·5/13 일일 클리핑 등장 (count: 2)

### [2] ...
(10건 반복)

---

**선택 요청**: 위 후보 중 최종 본문에 포함할 항목을 알려주세요.
예시 응답:
- `자본시장 1~5 / 거래 1~5`
- `자본시장 1,3,5,7,9 / 거래 2,4,6,8,10`
- 둘 다 5건 또는 3~5건 권장 (Monday Brief 페이지당 통상 3~4건)
```

여기서 멈추고 사용자 응답을 기다린다.

---

## Phase 2: 최종본 생성 + 저장

사용자 선택을 받은 후:

### Step 2-1) 선택 파싱
"자본시장 1,3,5,7,9 / 거래 2,4,6,8,10" 형식 파싱. 범위(`1~5` / `1-5`)와 콤마 리스트 모두 지원.

### Step 2-2) 최종 MD 생성 → `./deals/{endDate}.md`

```markdown
# 💼 Weekly Deal Flow — 2026년 5월 15일 (W/E 2026-05-15)

> 데이터 기준: 2026-05-11(월) ~ 2026-05-15(금) — 더벨, 딜사이트, 인베스트조선 등
> Phase 0 신호: 일일 news-clipping 5건 누적 신호 반영

## 1. 자본시장 동향

### 헤드라인 (2026.05.12)
- bullet 1 (텔레그래픽, **숫자**·% 강조)
- bullet 2
- bullet 3
- **출처**: [더벨](url)

### 다음 헤드라인 (2026.05.11)
...

## 2. 주요 거래 동향

### 헤드라인 (2026.05.11)
- bullet
- bullet
- **재무**: 매출 7,186억 / EV 1,641억 / EBITDA 356억 / **EV/EBITDA 4.6x**
- **출처**: [더벨](url)

#### Valuation (단위: 억원, FY25 기준)

| 항목 | 값 |
|---|---|
| Deal Type | Buyout |
| 매출액 | 7,186 |
| 영업이익 | 324 |
| 감가상각비(D&A) | 32 |
| EBITDA |  |
| 당기순이익 | 274 |
| 단기차입금 |  |
| 유동성장기차입금 |  |
| 유동리스부채 |  |
| 장기차입금 |  |
| 리스부채 |  |
| 현금및현금성자산 | 1,355 |
| 단기금융상품 | 4 |
| Deal Value | 3,000 |
| % Stake | 100 |
| 시가총액 |  |

### 다음 헤드라인 ...

## 3. Deal Summary

| 기업 | Deal Type | 거래 규모 추정 | EV/EBITDA | 비고 |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |
```

**Valuation 블록 규칙** (Page 6만, 선택):
- `#### Valuation (단위: 억원, FY25 기준)` H4 + 2열 마크다운 테이블 (현 시점 작년 = 직전 결산 = FY25; 매년 1월 이후 FY+1)
- 필수 행 17개 (Excel `Wekkly_Deal_2026xQ.xlsx` 시트 템플릿과 일치):
  Deal Type / 매출액 / 영업이익 / 감가상각비(D&A) / EBITDA / 당기순이익 / 단기차입금 / 유동성장기차입금 / 유동리스부채 / 장기차입금 / 리스부채 / 현금및현금성자산 / 단기금융상품 / Deal Value / % Stake / 시가총액
- 모르는 값은 빈 칸 → 대시보드가 입력 가능한 폼으로 렌더링 → 사용자 수기 입력 시 IBD·NetDebt·EV·Equity·EV/EBITDA·EV/매출·PER·Premium 라이브 계산
- **EBITDA**는 비워두면 `영업이익 + 감가상각비(D&A)` 자동 계산 (직접 입력 시 그 값 우선)
- **상장사 minority 거래**(예: 한화→KAI): 시가총액 행을 채우면 Equity Value의 fallback
- 데이터 출처: 상장사 DART 사업보고서, 외감대상 비상장사 DART 감사보고서, 사업부 분리는 모회사 부문별 데이터, 비공개는 보도자료 추정

### Step 2-3) 인덱스 갱신 → `./deals/index.json`
`dates` 배열 맨 앞에 `{endDate}` 추가 (이미 있으면 갱신만, 내림차순 유지).

### Step 2-4) 채팅 출력 + 배포 안내
저장된 최종 MD를 그대로 채팅에 표시 + 마지막에:
```
✅ 저장 완료 — ./deals/2026-05-15.md
👉 http://localhost:8000/#deals 새로고침 시 새 주차 pill 표시됨
👉 Cloudflare 배포: powershell -ExecutionPolicy Bypass -File .\deploy-snapshot.ps1
```

---

## 진행 체크리스트 (v2)

- [ ] **Phase 0** — `./news/{Mon~Fri}.md` 5건 Read → Deal 섹터 헤드라인 추출 → 누적 신호 맵 구축
- [ ] **이전 주차** `./deals/{prev-friday}.md` 도 참고 → 중복 회피 + 후속 진전 추적
- [ ] **Phase 1 1차 fetch** — thebell 0103 / dealsite 080000 / dealsite 075000 / investchosun 페이지 1~3
- [ ] **1순위 PE/LP/자문사/빅딜 점검** — 위 Step 1-2 리스트 매주 의무 검색
- [ ] **각 후보 scoring** — Phase 5/6 공식 가중평균 적용, score_breakdown 같이 표시
- [ ] **카테고리 다양성** — Page 5에서 최소 3개 카테고리 분포, Page 6에서 최소 4개 카테고리 분포
- [ ] **매체 다양성 체크** — 한 페이지 안에서 같은 매체 3건 이상 연속 금지
- [ ] **URL 날짜 메커니컬 검증** — 그 주 + 이전 주말 7일 외면 즉시 폐기
- [ ] **출처 URL과 본문 일치 검증** — 다른 사안 매핑 금지
- [ ] **텔레그램·증권사 데스크 언급 없음** 최종 확인
- [ ] **Page 6 Valuation 의무** — 거래 규모·지분율·배수·자금조달·자문사 명시 (비공개면 표기)
- [ ] **Phase 1 종료 → 사용자 선택 대기** — 자동 저장 금지
- [ ] **Phase 2** — MD 저장 + index.json 갱신 + 채팅 출력 + 배포 안내

---

## 자동 실행 시 동작

스케줄러(`weekly-deal-flow`, 매주 금요일 16:00 KST)로 자동 호출되는 경우:
- Phase 0 → Phase 1까지만 진행. 후보 10+10건을 채팅에 출력 후 멈춤
- 사용자가 별도 세션을 열어 응답하면 Phase 2 진행
- **자동으로 선택을 가정해 파일 저장 금지**
- 스케줄러 SKILL.md는 리포 디렉토리로 `cd` 후 이 명령을 호출하도록 설정해야 함

---

## 비용 / 과금
이 명령은 Claude Code 세션 내 WebSearch/WebFetch + Read/Write로만 동작 — **별도 Anthropic API 과금 없음**.

## 톤·구조 레퍼런스
과거 PDF (`Monday-Morning-Update_*.pdf`) + Excel valuation 템플릿 (`Wekkly_Deal_2026xQ.xlsx`). 협업자 환경에 PDF/Excel 없어도 이 문서가 명세를 모두 포함.
