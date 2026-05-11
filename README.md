# Reverent Partners — Live Dashboard

실시간 시장 데이터 + 경제 캘린더 + 뉴스 클리핑 통합 대시보드.
Yahoo Finance + Investing.com 데이터 fetcher (PowerShell) + 정적 HTML/CSS/JS 프론트엔드 + Claude API AI 채팅.

## 팀 협업 (Git 워크플로)

```
GitHub Enterprise (회사 계정, private repo)
        ↑↓ git push/pull
┌───────┴───────┬───────────────┬───────────────┐
PC A          PC B            PC C
- git clone   - git clone     - git clone
- serve.ps1   - serve.ps1     - serve.ps1
  localhost:8000  localhost:8000  localhost:8000
- 각자 자기 PC 브라우저로 확인
```

### 처음 합류하는 팀원

```powershell
# 1. 클론 (위치는 OneDrive 밖이어야 안전 — 예: C:\Users\<you>\code\)
cd C:\Users\<you>\code
git clone <GHE-repo-url> reverent-dashboard
cd reverent-dashboard

# 2. AI 채팅용 API key 본인 것 발급 후 config.json 생성
copy config.json.example config.json
# config.json 열어서 "ANTHROPIC_API_KEY" 값을 본인 키로 교체
# (https://console.anthropic.com/ Settings → API Keys)

# 3. 서버 실행
.\START.bat
# 또는: powershell -ExecutionPolicy Bypass -File .\serve.ps1
```
브라우저는 자동으로 http://localhost:8000 으로 열림.

### 변경 작업 흐름

```powershell
# 1. 최신 상태로 sync
git pull

# 2. 새 브랜치 (선택)
git checkout -b feat/your-feature

# 3. 코드 편집 (Claude Code, VS Code 등)

# 4. 커밋 & 푸시
git add -A
git commit -m "describe what changed"
git push -u origin feat/your-feature

# 5. GHE 웹에서 Pull Request 생성 → 동료 리뷰 → 머지
```

## 디렉토리 구조

```
reverent-dashboard/
├── index.html              # 페이지 셸 (사이드바 + 3개 뷰)
├── styles.css              # 통합 스타일
├── app.js                  # 시장 데이터 + 캘린더 + 뉴스 렌더링 + 뷰 라우터
├── chat.js                 # AI 채팅 위젯
├── macro.js                # 매크로 지표 정적 fallback
├── serve.ps1               # 통합 HTTP 서버 (정적 파일 + /refresh + /chat + /news/list)
├── refresh.ps1             # Yahoo Finance 시장 데이터 fetcher
├── fetch-calendar.ps1      # Investing.com 경제 캘린더 fetcher
├── system-prompt.txt       # AI 채팅용 한글 시스템 프롬프트 (UTF-8)
├── config.json.example     # API 키 템플릿 (커밋됨)
├── config.json             # 개인 API 키 (gitignore, 각자 작성)
├── START.bat               # 더블클릭 런처
├── news/                   # 일일 뉴스 클리핑 markdown (.md) 누적
└── README.md
```

런타임에 생성/갱신되는 파일 (gitignore):
- `data.json`, `calendar.json`, `calendar-week.json` — fetcher가 만드는 캐시
- `server.log`, `server.err` — 서버 로그
- `config.json` — 개인 API key

## 페이지 구성

| 사이드바 메뉴 | 뷰 | 데이터 소스 |
|---|---|---|
| 📊 Dashboard | 매크로 + 자본시장 + 섹터 | Yahoo Finance (33 ticker) + Investing.com (오늘 발표) |
| 📅 Weekly Calendar | 이번주 경제 지표 (날짜별) | Investing.com (이번주, 미국/한국/일본) |
| 📰 News Clipping | 일일 6섹터 뉴스 카드 | `news/YYYY-MM-DD.md` (`/news-clipping` 슬래시 명령이 생성) |

## 데이터 갱신 (수동 모드)

자동 갱신 비활성. 사이드바 하단 **↻ 지금 갱신** 버튼이 유일한 트리거 → Yahoo + Investing 동시 fetch (~12초). 외부 API rate limit / Cloudflare anti-bot 회피를 위해 의도된 설계.

## AI 채팅 (Claude Opus 4.7)

대시보드 우하단 💬 **AI Analyst** 버튼.

### 사용 전 1회 설정
1. https://console.anthropic.com/ → Settings → API Keys → Create Key
2. `config.json.example` → `config.json`으로 복사
3. `ANTHROPIC_API_KEY` 값에 본인 키 (`sk-ant-api03-...`) 입력

### 비용
- Claude Opus 4.7: input $5 / output $25 (per 1M tokens)
- Prompt caching: 시스템 프롬프트 + 대시보드 JSON 데이터 → 5분 캐시 → 첫 질문 후 ~90% 절감
- 예상 비용/질문: 첫 질문 ~$0.05, 캐시 hit ~$0.01

### 데이터 컨텍스트
매 요청마다 서버가 자동으로 `data.json` + `calendar.json`을 시스템 프롬프트에 bundle. AI는 항상 현재 시점 데이터로 답변.

## 뉴스 클리핑 (Daily News Clipping)

매일 09:03 KST 자동 실행되는 6섹터 뉴스 클리핑 시스템.
- 트리거: 슬래시 명령 `/news-clipping` 또는 scheduled task `daily-news-clipping`
- 출력: 채팅 markdown + `news/YYYY-MM-DD.md` 파일 동시 저장
- 대시보드는 `news/*.md`를 자동으로 카드 뷰로 표시

스케줄링은 사용자 레벨 (`~/.claude/scheduled-tasks/daily-news-clipping/`)이므로 각 팀원이 자기 PC에서 별도로 설정. 결과 markdown은 Git을 통해 공유됨.

## 트러블슈팅

| 증상 | 원인 / 해결 |
|------|-------------|
| "config.json missing or API key not set" | `config.json.example`을 `config.json`으로 복사하지 않았거나 키 미입력 |
| "401 authentication_error" | API 키 오타 또는 만료 — 콘솔에서 재발급 |
| "529 overloaded_error" | Anthropic 일시 과부하 — 잠시 후 재시도 |
| Investing.com fetch 403 | Cloudflare anti-bot — 5~30분 후 자동 해제 |
| 포트 8000 충돌 | 다른 프로세스가 사용 중 — `serve.ps1` `-Port` 인자 변경 |
| OneDrive 동기화 충돌 | 이 repo가 OneDrive 폴더 내부에 있으면 발생. 반드시 `~/code/` 같은 외부 위치 사용 |

## 향후 확장 후보
- 반도체 섹터 상세 (PER/PBR/시총)
- 수출입 동향 (관세청 OpenAPI)
- IPO 현황 (KIND)
- Deal Flow 페이지 (이미 사이드바 placeholder 존재)
