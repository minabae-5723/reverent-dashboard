---
description: 주간 GitHub Tech Radar — 관심 테마의 급상승·신규 repo를 star velocity·구조 지표로 큐레이션 (투자 선행지표). 후보 제시 → 사용자 선택 → MD 저장
---

# GitHub Tech Radar — Weekly **v1**

매주 1회 루틴. 글로벌 테크 트렌드의 **선행 지표(leading indicator)**로서 GitHub 활동을 추적한다. 새 기술 패러다임은 보통 언론·애널리스트 리포트·매출보다 먼저 GitHub의 star/fork/contributor 곡선에서 폭발한다 — 이 신호를 개인 투자·투자 심사에 쓸 수 있게 큐레이션한다.

> **핵심 원칙 (주식의 거래량·모멘텀 논리와 동일)**: star **절대값은 거의 무의미**하다. 보는 것은 ① star **velocity**(증가 속도), ② **fork/star 비율**(실제로 코드를 가져다 쓰는가 vs 단순 북마크), ③ **contributor 증가·집중도**, ④ **issue/PR cadence**(생태계가 살아있는가), ⑤ **신선도×속도**(생성 직후 폭발이 가장 강한 신호). Runa Capital ROSS Index가 제도화한 방법론의 미니 버전.

> **실행 위치**: 리포 루트(`reverent-dashboard/`)에서 실행. CWD가 다르면 `./github/` 상대 경로가 안 맞는다.

> **톤**: 산출물은 **음슴체**(`~함`, `~임`, `~됨`, `~보임`) — news-clipping/deal류와 동일. 헤드라인·repo명은 원문 유지.

---

## 데이터 소스 (모두 무료·무인증·WebFetch — 별도 API 과금 없음)

### 1차 소스 A — GitHub Trending (속도 신호의 1차)
`stars this week`를 직접 반환하므로 velocity 계산 불필요. 언어별로 병렬 fetch.
```
WebFetch  https://github.com/trending?since=weekly                       (전체)
WebFetch  https://github.com/trending/python?since=weekly
WebFetch  https://github.com/trending/typescript?since=weekly
WebFetch  https://github.com/trending/rust?since=weekly
WebFetch  https://github.com/trending/go?since=weekly
```
프롬프트에서 각 repo의 **full_name / description / language / total stars / stars this week**를 추출하라고 지시.

### 1차 소스 B — GitHub Search API (테마 정밀 발굴 + 신규 폭발 탐지)
무인증 작동 확인됨(`incomplete_results:false`). `created:>{N주 전}` + `stars:>{임계}` + `sort=stars`로 쿼리하면 **"짧은 기간에 임계 star를 돌파한 repo" = 고velocity가 구조적으로 보장**된다.
```
WebFetch  https://api.github.com/search/repositories?q=topic:{TOPIC}+created:%3E{8주전}+stars:%3E300&sort=stars&order=desc&per_page=20
```
- URL 인코딩: `>` → `%3E`, 공백 → `+`
- `{8주전}` = 명령 실행일 − 56일 (YYYY-MM-DD)
- 프롬프트에서 `full_name / stargazers_count / forks_count / created_at / pushed_at / open_issues_count / description / owner.login` 추출 지시

각 테마 토픽은 아래 테마 정의표 참조. 테마당 1쿼리.

---

## 추적 테마 (하이브리드 — GitHub-native 우선, 기존 6섹터 매핑)

GitHub에서 **신호가 풍부한 테마를 native로 깊게**, 신호가 얕은 섹터는 가볍게 매핑한다.

| # | 테마 | GitHub topic / 검색 키워드 | 기존 섹터 매핑 | 신호 밀도 |
|---|---|---|---|---|
| 1 | **AI Agents / Autonomous** | `topic:ai-agent` `topic:agents` `topic:autonomous-agents` `topic:multi-agent` | IT SW | 🔥🔥🔥 |
| 2 | **LLM / Inference / Serving** | `topic:llm` `topic:llmops` `topic:inference` `topic:llm-serving` | IT SW | 🔥🔥🔥 |
| 3 | **RAG / Retrieval / Vector DB** | `topic:rag` `topic:vector-database` `topic:embeddings` `topic:retrieval` | IT SW / Tech Infra | 🔥🔥 |
| 4 | **Coding Assistants / DevTools** | `topic:code-generation` `topic:ai-coding` `topic:developer-tools` `topic:copilot` | IT SW | 🔥🔥🔥 |
| 5 | **AI Infra / MLOps / Orchestration** | `topic:mlops` `topic:machine-learning-ops` `topic:orchestration` `topic:gpu` | Tech / Data Infra | 🔥🔥 |
| 6 | **Robotics / Embodied AI** | `topic:robotics` `topic:ros` `topic:embodied-ai` `topic:humanoid` | Defense / Electrification | 🔥 |
| 7 | **Data / Analytics Infra** | `topic:data-engineering` `topic:database` `topic:streaming` `topic:olap` | Tech / Data Infra | 🔥🔥 |

- 매주 **1~5번(AI 코어)은 의무**, 6~7번은 신규·급상승이 있을 때만 1~2건.
- Bio·Defense·Deal은 GitHub 신호가 구조적으로 얕음 → 별도 섹션 X. 단 해당 영역에서 폭발하는 OSS가 보이면 "📌 섹터 노트"로 1~2줄 언급.

---

## Phase 1: 후보 발굴 + 스코어링

### Step 1-1) 직전 주차 참고 (중복·추세 추적)
`./github/` 폴더의 가장 최근 MD가 있으면 Read → 이미 다룬 repo 목록 + 그때의 stars 기록. **이번 주 신규 진입**과 **연속 등장 시 velocity 변화(가속/감속)**를 추적하기 위함.

### Step 1-2) 1차 소스 fetch
- Trending 5개(전체+4개 언어) 병렬 WebFetch
- Search API 테마 1~5번 각각 WebFetch (`created:>{8주전} stars:>300`), 6~7번은 선택적

### Step 1-3) 후보 풀 병합 + 정규화
모든 결과를 `full_name` 기준 dedup. 각 repo에 대해 다음 필드 정규화:
```json
{
  "repo": "owner/name",
  "url": "https://github.com/owner/name",
  "desc": "한 줄 설명 (영문 원문 → 필요시 한국어 보충)",
  "lang": "Python",
  "theme": "AI Agents",
  "stars_total": 24096,
  "stars_week": 13159,          // Trending 출처. Search-only repo는 null
  "forks": 1820,
  "created_at": "2026-03-18",
  "pushed_at": "2026-05-27",
  "age_days": 72,               // 실행일 − created_at
  "fork_star_ratio": 0.076,     // forks / stars_total
  "owner_type": "회사/개인/재단/익명",  // owner.login으로 판단
  "company_link": "이 repo 배후 회사·스타트업 (있으면) — 투자 관점 핵심"
}
```

### Step 1-4) 🚩 Fake-star / 노이즈 필터 (먼저 거른다)
GitHub Search에는 **인위적 star 부풀리기(fake-star) repo**가 섞인다. 다음 패턴은 **후보에서 제외하거나 🚩 플래그**:
- 생성 8주 미만인데 stars 5만+ & **fork/star < 0.02** (거의 안 가져다 씀 = 북마크/봇 의심)
- `pushed_at`이 생성 직후 1~2회 뒤로 멈춤 (커밋 활동 없이 star만 폭증)
- owner가 개인 + README만 있고 실코드 없음 (어워섬리스트·튜토리얼 모음은 트렌드 참고용으로만, 투자 신호 아님 → 별도 표기)
- 같은 owner가 동일 패턴 repo 다수 양산

> 단순 awesome-list·학습자료·프롬프트 모음은 **"트렌드 온도계"로는 의미** 있으나 **투자 신호로는 약함** → `📚 학습자료` 태그로 구분.

### Step 1-5) 스코어링 (0~10, 가중평균) — 속도·구조 중심
```
score = 0.35 × velocity        # stars_week 또는 (stars_total / age_days × 7) 환산 주간속도
      + 0.25 × adoption        # fork/star 비율 — 실사용 신호
      + 0.20 × freshness        # 신선도 — 생성 8주 내 폭발이 최강
      + 0.10 × activity         # pushed_at 최근성 (7일내 10 / 30일 6 / 그이상 2)
      + 0.10 × invest_relevance # 배후 회사·경쟁구도·투자 매핑 가능성
```
**velocity 척도**: 주간 +5000★↑ →10 / +2000 →8 / +1000 →6 / +500 →4 / +200 →2
**adoption(fork/star) 척도**: ≥0.15 →10 / 0.08 →7 / 0.04 →5 / 0.02 →3 / <0.02 →1(🚩)
**freshness 척도**: age ≤30일 →10 / ≤56일 →8 / ≤180일 →5 / ≤1년 →3 / 그이상 →1
**invest_relevance 척도**: 식별된 스타트업/상장사 제품·핵심 OSS →10 / 유명 재단·빅테크 →7 / 배후 불명 유망 →4 / 개인·학습자료 →1

### Step 1-6) 투자 관점 주석 (각 후보의 핵심 — 이게 차별점)
repo가 단순 코드가 아니라 **투자 맥락**과 연결되도록:
- **배후 식별**: 이 repo가 어떤 회사/스타트업의 핵심 제품인가? (예: Next.js→Vercel, repo명·org·README·홈페이지로 추론). 비상장 OSS-first 회사면 ⭐ 표시 — star velocity가 ARR 성장의 선행 프록시일 수 있음.
- **경쟁 구도**: 같은 테마 내 경쟁 repo와의 상대 속도 (예: "에이전트 프레임워크 X가 LangChain 대비 주간 속도 2배").
- **상장사 연결**: 빅테크/상장사 org가 낸 OSS면 해당 종목과 연결 (예: anthropics, openai 관련은 직접 비상장이나 생태계 신호).
- **한국 연결**: owner location·README 언어·기여자로 한국팀 추정되면 📍 표시 (희소하므로 가치 높음 — 별도 섹터 III 참조).

### Step 1-7) 채팅 출력 (후보 12~18건, 테마별 그룹)
```markdown
# 🛰️ GitHub Tech Radar 후보 — 2026-05-29 주차
> Trending(주간) 5개 언어 + Search API 테마 5개 스캔 · 직전 주차 대비 추적 · fake-star 3건 제외(🚩)

## 🔥 이번 주 최고 속도 (Top Movers)
### [1] owner/repo · *AI Agents* · score 9.4 · ⭐배후: 비상장 스타트업 XYZ
- 주간 **+13,159★** (누적 24,096) · fork/star **0.08** · 생성 72일 · 최근커밋 2일전
- 무엇임: (한 줄). 왜 뜨는지: (한 줄)
- 💡 투자: 배후 XYZ는 시리즈 A 추정 · 동일테마 경쟁 ABC 대비 주간속도 약 2배 · 상장 comps: ___
- 🔗 https://github.com/owner/repo

### [2] ...

## 🆕 신규 폭발 (생성 8주 내)
### [n] ...

## 📈 연속 가속 (직전 주차 대비 속도↑)
### [n] ... (지난주 +3,000 → 이번주 +6,000, 가속)

## 📚 트렌드 온도계 (학습자료·모음 — 참고용, 투자신호 약함)
- owner/repo (+8,000★, "754개 사이버보안 스킬 모음") — AI 에이전트 스킬화 흐름 방증

## 📌 섹터 노트 (Bio·Defense·Electrification 등 GitHub 얕은 영역)
- (해당 영역 폭발 OSS 있으면 1~2줄, 없으면 "특이 신호 없음")
```
여기서 **멈추고 사용자 선택을 기다린다**. (자동 실행 시에도 여기까지만 — 자동 저장 금지)

**선택 요청 예시**:
- `1,2,4,7 저장` / `Top Movers 전체 + 신규 2,3`
- 보통 6~10건 권장

---

## Phase 2: 최종본 + 저장

사용자 선택을 받은 후:

### Step 2-1) 최종 MD → `./github/{YYYY-MM-DD}.md` (파일명 = 그 주 토요일 또는 실행일)
```markdown
# 🛰️ GitHub Tech Radar — 2026년 5월 29일 주차

> 데이터 기준: GitHub Trending(주간) + Search API · 스캔일 2026-05-29
> 측정: star velocity · fork/star · 신선도 · 활동성 (절대 star 아님)

## 1. Top Movers (이번 주 최고 속도)

### owner/repo — *AI Agents*
- 주간 **+13,159★** / 누적 24,096 / fork·star **0.08** / 생성 2026-03-18(72일) / 최근커밋 2026-05-27
- 무엇임 (1~2문장, 음슴체)
- **💡 투자 시사**: 배후 회사 · 경쟁 구도 · 상장/비상장 comps · 한국 연결(있으면)
- **🔗 출처**: [owner/repo](https://github.com/owner/repo)

## 2. 신규 폭발
...

## 3. 연속 가속 / 감속
...

## 4. 섹터 노트
...

## 5. Watch Table (이번 주 스냅샷 — 다음 주 델타 추적용)
| repo | theme | ★total | ★week | fork/★ | created | 비고 |
|---|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... | ... |
```
> **Watch Table 의무**: 다음 주 실행 시 Step 1-1에서 이 표를 읽어 velocity 변화(가속/감속)를 계산하므로 **선택된 repo는 전부 표에 기록**.

### Step 2-2) 인덱스 갱신 → `./github/index.json`
`dates` 배열 맨 앞에 파일명 날짜 추가 (내림차순, 중복이면 갱신만).

### Step 2-3) 채팅 출력 + 안내
저장된 최종 MD를 채팅에 표시 + 마지막에:
```
✅ 저장 완료 — ./github/2026-05-29.md
👉 (대시보드 #github 페이지 연동 후) http://localhost:8000/#github 에서 카드 뷰
👉 배포: powershell -ExecutionPolicy Bypass -File .\deploy-snapshot.ps1
```

---

## ⛔ Hard Rules
- **절대 star 순위 금지** — 항상 velocity·fork/star·신선도로 줄 세움. 누적 star 큰 노포 repo는 신호 약함.
- **fake-star 필터 의무** — Step 1-4 패턴 점검 후에만 후보 확정. 의심 repo는 🚩 + 제외/강등.
- **awesome-list·튜토리얼·프롬프트 모음**은 투자 신호와 분리(`📚` 태그) — 온도계로만.
- **배후 회사 추정은 공개 정보 한정** — repo·org·README·공개 홈페이지·공개 펀딩 보도까지만. 개인 기여자 사생활 분석 금지.
- **한국 연결은 신중히** — location·repo 메타데이터 등 공개 정보로만, 추정은 "추정" 명시.
- **수치는 fetch 시점 명시** — GitHub 수치는 실시간 변동. "스캔일 기준" 표기.
- **투자 시사는 신호일 뿐 권유 아님** — "선행지표·정성신호"로 프레이밍, 매수·매도 단정 금지.

---

## 자동 실행 시 동작
스케줄러로 호출되면 Phase 1까지만(후보 출력 후 정지). 사용자가 응답하면 Phase 2. **자동 저장 금지.**

## 비용 / 과금
WebFetch + Read/Write만 사용 — **별도 Anthropic API 과금 없음**. (GitHub 무인증 한도: Search API 분당 10건, Trending 무제한. 테마 5~7개 + Trending 5개 = 회당 12~14 fetch로 한도 내.)
