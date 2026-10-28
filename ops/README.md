# 운영 이관 · 공동관리 (ops/)

이 대시보드는 **GitHub(main) = 원본**이고, 각 PC는 clone을 돌리는 실행기일 뿐입니다.
코드·데이터는 git으로 오가기 때문에 어느 PC든(사무실 PC, 상시 켜둔 PC/VM) 같은 방식으로 띄울 수 있습니다.

| 무엇 | 어디에 | PC 바꿀 때 |
|---|---|---|
| 코드 · 데이터 · 큐레이션 md | 이 리포 (GitHub) | `git clone` |
| 자동 배포 Windows 작업 6개 | `ops/tasks.json` | `ops/install.ps1`이 등록 |
| 숨김 실행기 | `ops/silent-ps.vbs` | 리포에 포함 |
| 어느 PC가 배포 담당인지 | `ops/hosts.json` | 이름 한 줄 고치고 push |
| API 키 (`config.json`) | 각 PC 로컬 (gitignore) | `install.ps1`이 입력받음 |
| Claude Code 예약작업 · 슬래시명령 · 리포트 다운로더 | **운영 번들** — 회사 SharePoint `Firm - Documents\General\reverent-dashboard-ops` (공개 리포 아님) | 번들의 `install.ps1` |

> 인수인계·비상시 이어받기 절차는 운영 번들의 `README.md`에 단계별로 있습니다. 이 문서는 리포 쪽 원리만 설명합니다.

## 역할 (ops/hosts.json)

여러 PC가 동시에 돌아가도 **배포·자동 push는 한 PC만** 하도록 역할을 둡니다.

```json
"roles": { "primary": "<PC 이름>", "us-close": "" }
```

- 값은 그 PC의 `COMPUTERNAME` (PowerShell에서 `$env:COMPUTERNAME`). 환경변수 `REVERENT_HOST_ID`가 있으면 그것을 대신 씁니다.
- `"*"` = 모든 PC, `""` = 아무도 안 함.
- `primary`: 07:00 DailyDeploy(미국장 마감 기준), 평일 15:45 KRClose(한국장 마감 기준), 금 16:30 FridayDeploy, Claude 예약작업 전부. (장중 5분 자동 갱신은 없음 — 대시보드 ↻ 버튼으로만 수동 갱신)
- `us-close`: 토 06:30 미국 마감 스냅샷 (현재 비활성).
- 담당이 아닌 PC는 해당 작업이 시작되자마자 조용히 종료합니다. RepoSync(5분 pull)와 KeepAlive(로컬 서버)는 모든 PC에서 돕니다.

현재 담당 확인:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\take-today.ps1 -Status
```

### 오늘 하루만 대타 (`today`)

기본 당번은 `roles.primary`에 그대로 두고, 특정 날만 다른 PC가 맡을 수 있습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\take-today.ps1            # 오늘은 이 PC가 당번
powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\take-today.ps1 -Release   # 같은 날 원래 당번에게 돌려주기
```

- `hosts.json`에 `"today": { "date": "<오늘>", "roles": { "primary": "<이 PC>" } }`가 기록되고 push됩니다.
- 그 날짜에만 `roles`보다 우선합니다. **다음 날이면 자동으로 무시**되어 원래 당번이 다시 맡습니다. 지울 필요가 없습니다.
- 예비 당번 PC에 운영 번들을 설치해 두었다면, Claude에게 "오늘 내가 RMM 당번이야"라고 말하는 것으로 위 명령 + 그날 이미 지나간 작업의 순차 실행까지 처리됩니다(번들의 `rmm-today` 스킬).

## 새 PC에 세팅하기

준비물: Git for Windows, GitHub 계정(회사 org `reverent-partners`의 `market-monitor` 팀 초대 수락), 본인 API 키들.

```powershell
cd C:\Users\<you>\code          # OneDrive 폴더 안은 피할 것
git clone https://github.com/reverent-partners/reverent-dashboard.git
cd reverent-dashboard
git fetch                       # 첫 인증 (브라우저 로그인 창)
powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\install.ps1
.\START.bat                     # http://localhost:8000
```

`install.ps1`은 다시 돌려도 안전합니다 (`-DryRun`으로 미리보기).
Claude Code 자동화와 리포트 다운로더는 운영 번들의 `install.ps1 -WithDownloader`로 설치합니다.

## 운영 담당 넘기기 (A → B)

1. B PC 세팅 완료 (위 절차 + 운영 번들 설치 + Claude 예약작업 등록).
2. `ops/hosts.json`의 `primary`를 B의 PC 이름으로 바꾸고 commit · push. 5분 안에 양쪽이 pull 하면 그 시점부터 A는 쉬고 B가 배포합니다.
3. A는 그대로 두면 **공동관리**(열람·수동 편집·user-state 저장 가능, 자동 배포만 안 함).
   완전히 손 떼려면 A에서 `ops\install.ps1 -Uninstall` 실행하고, A의 Claude 예약작업을 끕니다.
4. 다음날 07:00 이후 GitHub 커밋 로그에 B 이름의 `Deploy snapshot`이 찍혔는지 확인.

되돌리기 = `hosts.json`을 원래 이름으로 다시 push.

## 공동관리 규칙

- **자동 배포는 담당 PC 하나만.** 두 PC가 동시에 primary면 배포 커밋이 서로 충돌합니다.
- 코드 수정은 브랜치 → PR → 머지. main 체크아웃은 자동 커밋이 계속 들어오므로 그 폴더에서 브랜치를 바꾸지 말 것 (작업용 사본은 `git worktree` 사용).
- 수기 입력값(`user-state.json`)은 어느 PC에서 저장해도 항목 단위로 병합됩니다 (`merge-userstate.ps1`).
- API 키는 각자 본인 것. 키를 채팅·메일·리포로 주고받지 않기.
