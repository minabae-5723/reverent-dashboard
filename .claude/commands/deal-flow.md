---
description: 주간 Monday Brief용 자본시장 동향 + 주요 거래 동향 큐레이션 (각 10개 후보 → 사용자 선택 → MD 파일 저장)
---

# Weekly Deal Flow — Monday Brief Section Curation

매주 금요일 16:00 KST 루틴. **Monday Morning Brief**의 *Page 5: 자본시장 동향* + *Page 6: 주요 거래 동향* 섹션을 채울 기사를 큐레이션해 대시보드 `/#deals` 페이지에 주차별로 적재한다.

> **실행 위치**: 이 명령은 **레포 루트에서 Claude Code를 실행해야** 한다. CWD = `reverent-dashboard/`. `./deals/` 상대 경로로 동작.

**2단계 워크플로우**:
- **Phase 1**: 그 주 금요일 기준 직전 5영업일(월~금) 기사 수색 → 각 페이지 10건 후보 카드 채팅 출력 → 사용자에게 선택 요청 ("자본시장 1,3,5,7,9 / 거래 2,4,6,8,10" 같은 형식)
- **Phase 2**: 사용자 선택 응답이 오면 최종 MD 본문 채팅 출력 + `./deals/YYYY-MM-DD.md` 파일 저장 + `./deals/index.json` 갱신

## 기준 날짜와 기간

- **endDate**: 명령 실행 시각(KST) 기준 그 주의 금요일 (월~목에 실행 시 다가오는 금요일, 토~일에 실행 시 직전 금요일)
- **startDate**: endDate − 4일 (월요일)
- **파일명**: `./deals/{endDate}.md` (예: `./deals/2026-05-15.md`)
- **헤더 표기**: `2026-05-11 ~ 2026-05-15`

## ⚠️ Reverent Partners 큐레이션 우선순위

### Page 5 — 자본시장 동향
1. 금융위·한은 등 당국 정책 변화 (국민성장펀드, 자본시장법, ETF 규제 등)
2. 한국 증시 주요 지표 (코스피·코스닥, 외국인 수급, 거래대금)
3. 환율·금리·외환보유액
4. IPO 시장 동향
5. 펀드 결성 / GP 선정 등 PEF 시장 인프라

### Page 6 — 주요 거래 동향
1. 조 단위 PE 빅딜 (바이아웃·세컨더리)
2. 그룹 카브아웃 (SK·한화·롯데 등 비핵심 자산 매각)
3. 우협 선정·본입찰 마감·SPA 체결 등 진행 단계 임박 딜
4. 기업간 전략적 인수 (수직계열화·볼트온)
5. 한국 PE 운용사 신규 펀드 / 리파이낸싱
6. 재무 데이터(EV·EBITDA·멀티플) 확보 가능한 딜 우선

## 카테고리 분류

- **Page 5**: `정책/규제 | 증시동향 | 금리/환율 | 펀드결성 | IPO | 자본시장 제도 | 기타`
- **Page 6**: `PE Buyout | 기업간 인수 | 매각 추진 | 우협 선정 | SPA 체결 | Pre-IPO/VC 투자 | 리파이낸싱 | 기타`

## 검색 소스 (allowed_domains)

1차: `thebell.co.kr` (자본시장 0103), `dealsite.co.kr` (M&A 080000), `investchosun.com`
2차: `hankyung.com` 마켓인사이트, `mk.co.kr`, `edaily.co.kr`, `mt.co.kr`, `fnnews.com`, `businesspost.co.kr`
보조: `bloter.net`, `einfomax.co.kr`, `fsc.go.kr`, `bok.or.kr`, `kcmi.re.kr`, `korea.kr`, `etoday.co.kr`, `newsis.com`, `news1.kr`, `biz.chosun.com`

**도구 접근성 메모**
- WebSearch 차단 도메인 (allowed에서 빼야 함): `reuters.com, wsj.com, ft.com, mk.co.kr, biz.chosun.com, yna.co.kr, apnews.com`
- WebFetch는 `thebell.co.kr/front/NewsList.asp?Code=0103`, `dealsite.co.kr/categories/080000` 두 페이지가 가장 안정적 (목록 1회 fetch로 그 주 헤드라인 다수 확보)
- 같은 거래의 중복 보도는 1건으로 통합

## Phase 1: 후보 카드 생성

### 1) 1차 fetch (병렬)
```
WebFetch  https://www.thebell.co.kr/front/NewsList.asp?Code=0103   → 헤드라인+날짜+URL 다수 추출
WebFetch  https://dealsite.co.kr/categories/080000                   → 동일
```
endDate 기준 직전 5영업일 + 직전 주말 보도분까지 확보. 검색이 부족하면 WebSearch 3~5회 추가 (`"2026년 5월 PE 인수 매각"` 같은 키워드).

### 2) 후보 추출 (각 페이지 10건)
**필수 필드**:
- `rank`: score 내림차순 1~10
- `title`: 보도자료 헤드라인 그대로 (또는 약간 단축, 60자 이내)
- `date`: `YYYY.MM.DD`
- `category`: 위 카테고리 분류 중 하나
- `score`: 1~10 (우선순위 가이드 기반)
- `bullets`: 2~4개, 핵심 사실 + 한국 IB 톤 (`~함`, `~임`, `~예상`, `~전망` 종결)
- `source`: 매체명 (더벨, 인베스트조선, 한국경제, 금융위 등)
- `url`: 원문 URL
- **Page 6 한정** `financials`: `매출 ___억 / EV ___억 / EBITDA ___억 / EV/EBITDA __x` (없으면 빈 문자열)

**bullets 작성 규칙**:
- 거래 규모·기업가치·멀티플·지분율 등 정량 정보 우선
- 굵게 강조는 마크다운 `**bold**` 사용
- 한 bullet에 여러 데이터 포인트 압축 (예: "한화에어로 KAI 지분 **5.09%** 확보, **5,000억원** 추가 투입해 연말 **8%** 목표")
- 마지막 bullet은 가능하면 시사점·변수·전망

### 3) 채팅 출력 형식

```markdown
# 📋 Weekly Deal Flow 후보 — 2026-05-11 ~ 2026-05-15

## 1. 자본시장 동향 후보 (10건)

### [1] 헤드라인 (2026.05.12) · *정책/규제* · score 9
- bullet 1
- bullet 2
- bullet 3
※ 출처: 더벨 · [원문](url)

### [2] ...
(10건 반복)

## 2. 주요 거래 동향 후보 (10건)

### [1] 헤드라인 (2026.05.11) · *PE Buyout* · score 10
- bullet 1
- bullet 2
- bullet 3
※ 재무: 매출 1,800억 / EV 4,500억 / EBITDA 480억 / EV/EBITDA 9.4x
※ 출처: 인베스트조선 · [원문](url)

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

## Phase 2: 최종본 생성 + 저장

사용자가 선택 응답을 보내면:

### 1) 선택된 항목 추출
입력 파싱 ("자본시장 1,3,5,7,9 / 거래 2,4,6,8,10" 같은 형식). 범위(`1~5` 또는 `1-5`)와 콤마 리스트 모두 지원.

### 2) 최종 MD 생성

`./deals/{endDate}.md` 에 아래 형식으로 저장 (실행 위치 = 리포 루트):

```markdown
# 💼 Weekly Deal Flow — 2026년 5월 15일 (W/E 2026-05-15)

> 데이터 기준: 2026-05-11(월) ~ 2026-05-15(금) — 더벨, 딜사이트, 인베스트조선 등

## 1. 자본시장 동향

### 헤드라인 (2026.05.12)
- bullet 1 (텔레그래픽, **숫자**·% 강조)
- bullet 2
- bullet 3
- **출처**: [더벨](url)

### 다음 헤드라인 (2026.05.11)
...

## 2. 주요 거래 동향

### 헤드라인 (2026.05.06)
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

### 다음 헤드라인 (2026.05.11)
...

## 3. Deal Summary

| 기업 | Deal Type | 거래 규모 추정 | 비고 |
|---|---|---|---|
| ... | ... | ... | ... |
```

**주의 사항**:
- 헤드라인 끝의 `(YYYY.MM.DD)` 패턴은 대시보드 파서가 인식 → 그대로 유지
- bullet 톤: `~함`, `~임`, `~예상`, `~전망` 명사형 종결 위주 (Monday Brief 일관성)
- `**bold**` 강조는 거래 규모·지분율·멀티플·당사자명 핵심에만
- Deal Summary 테이블은 Page 6 선택 항목 기반 작성 (Page 5는 보통 테이블 미포함)
- 출처는 마지막 bullet으로 `**출처**: [매체명](url)` 형식

**Valuation 블록 (Page 6 거래만, 선택)**:
- `#### Valuation (단위: 억원, FY25 기준)` H4 + 2열 마크다운 테이블 (현 시점 작년 = 직전 결산 = FY25; 매년 1월 이후 FY+1)
- 필수 행: Deal Type / 매출액 / 영업이익 / 감가상각비(D&A) / EBITDA / 당기순이익 / 단기차입금 / 유동성장기차입금 / 유동리스부채 / 장기차입금 / 리스부채 / 현금및현금성자산 / 단기금융상품 / Deal Value / % Stake / 시가총액
- 행 순서는 위 그대로 (Excel `Wekkly_Deal_2026xQ.xlsx` 시트 템플릿과 일치)
- 값을 모르면 빈 칸으로 둠. 대시보드가 입력 가능한 폼으로 렌더링 + IBD·Cash·NetDebt·EV·EquityValue·EV/EBITDA·EV/매출·PER·Premium을 라이브 계산
- **EBITDA**는 비워두면 `영업이익 + 감가상각비(D&A)` 로 자동 계산. 직접 입력 시 그 값 우선
- **상장사 minority 거래**(예: 한화→KAI): Deal Value/% Stake 두 칸을 비우거나 정확히 입력 — 시가총액 행을 채우면 Equity Value의 fallback으로 사용됨
- 데이터 출처: 상장사는 DART 사업보고서, 외감대상 비상장사는 DART 감사보고서, 사업부 분리는 모회사 사업부문 별 데이터. 비공개 자산은 보도자료 추정치만 기입

### 3) 인덱스 갱신

`./deals/index.json`을 읽어 `dates` 배열 맨 앞에 `{endDate}` 추가 (이미 있으면 갱신만, 내림차순 유지):

```json
{"dates": ["2026-05-15", "2026-05-08", ...]}
```

### 4) 채팅 출력

저장된 최종 MD를 그대로 채팅에 표시 + 마지막에 한 줄로 요약:
```
✅ 저장 완료 — ./deals/2026-05-15.md
👉 http://localhost:8000/#deals 새로고침 시 새 주차 pill 표시됨
👉 배포: powershell -ExecutionPolicy Bypass -File .\deploy-snapshot.ps1
```

## 자동 실행 시 동작

스케줄러(`weekly-deal-flow`, 매주 금요일 16:00 KST)로 자동 호출되는 경우:
- Phase 1까지만 진행. 후보 10+10건을 채팅에 출력 후 멈춤 (사용자 선택 대기)
- 사용자가 별도 세션을 열어 응답하면 Phase 2 진행
- **자동으로 선택을 가정해 파일 저장 금지** — 매주 사용자 큐레이션이 핵심
- 스케줄러 SKILL.md는 리포 디렉토리로 `cd` 후 이 명령을 호출하도록 설정해야 함 (그래야 `./deals/` 상대 경로가 올바르게 작동)

## 톤·구조 레퍼런스

과거 PDF 파일들은 큐레이션 톤·문장 길이·종결어미·강조 패턴의 reference. 협업자 환경에 PDF가 없으면 이 슬래시 명령 문서가 명세를 모두 포함하므로 PDF 없이도 동일 결과 산출 가능.

## 비용 / 과금

이 명령은 Claude Code 세션 내에서 WebSearch/WebFetch + Read/Write로만 동작 — **별도 Anthropic API 과금 없음**.
