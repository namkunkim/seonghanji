> Task ID: Q-05-QA-01 — 로컬·원격 CI 동등성 및 실패 검출 수용
>
> 공식 제목: 로컬·원격 CI 동등성 및 실패 검출 수용
>
> 상태: PARTIAL — Q-06-01에서 fresh-import race와 campaign 400회 시간 계약을 교정함; 정상 전체 gate·원격 수용 재실행 필요

# Q-05-QA-01 로컬·원격 CI 동등성 및 실패 검출 수용

## 수용 기준과 증거 방식

로컬은 다음 명령 하나로 실행한다.

```powershell
& .\tools\ci\run_quality_gate.ps1
```

원격은 같은 PowerShell 실행기에 CI가 내려받은 Godot 4.7.2 console 경로와 로그 경로를 넘긴다. 따라서 다음 순서는 단일 소스에서 동일하다: version/import, 전체 단위시험, 잠금 ruleset 100회 캠페인, 국력·예산·적벽·글리프 검산, 저장·복원, 명령 로그 재생, A-05, G-10 E2E.

| 검증 | 정상 기준 | 음성 기준 | 최종 증거 |
|---|---|---|---|
| 통합 정상 실행 | 11단계 모두 PASS, aggregate 0 | 해당 없음 | 로그 요약과 종료 코드 |
| 단위시험 | assertion/section 하한 충족 | 격리 사본에서 단언 실패 → aggregate 1 | 해당 단계 및 aggregate 로그 |
| 검산기 | 네 검산기 모두 0 | fixture/기대값 불일치 → verifier 및 aggregate 1 | 기대값·실제값 출력 |
| 캠페인 잠금 | 100회 잠금 지표 PASS | 잠금 기준 위반 → aggregate 1 | campaign 로그 |
| 저장 경로 | `user://` save/restore PASS | 쓰기 불가 user data → aggregate 1 | save/restore 로그 |
| 계속 실행 | 전체 결과가 남음 | 한 초기 단계 실패 뒤 후속 단계가 실행됨 | summary의 모든 행 |

음성 검증은 원본 트리에 파손을 남기지 않는 임시 사본 또는 격리 worktree에서만 수행한다. `SKIP` 추가, 기대 정본 변경, 또는 실패를 성공으로 바꾸는 방식은 수용하지 않는다.

## 실행 결과 기록

| 항목 | 결과 |
|---|---|
| 로컬 정상 통합 실행 | **재실행 대기** — Q-05의 110초 banner-only 관찰은 `run_campaign.gd`가 실제로 400회(표준 100+HB 3×100)를 수행한다는 계약을 놓친 조기 중단이었다. Q-06-01이 fresh import와 900초 campaign timeout을 교정했으며, 변경 HEAD에서 aggregate 0을 다시 확인해야 한다. |
| 단위시험 의도적 실패 | 격리 시험 후 기록 |
| 검산기 의도적 불일치 | 격리 시험 후 기록 |
| 단언 수 하한 미달 | 격리 시험 후 기록 |
| 잠금 ruleset 위반 | 격리 시험 후 기록 |
| 저장 경로 쓰기 실패 | 격리 시험 후 기록 |
| 실패 뒤 후속 단계 실행 | 격리 시험 후 기록 |
| 원격 workflow 생성/실행 commit SHA | push 후 GitHub Actions 조회로만 기록 |
| 원격 job 결과 | 조회 불가 시 PARTIAL (PASS 추정 금지) |

## 2026-09-08 중간 관찰

정상 실행 중 import와 단위시험은 통과했다. 첫 시도에서 검산기 4종, save/restore, A-05, G-10은 모두 0으로 끝났고, 실패한 campaign 단계 뒤에도 이 결과들이 모두 summary에 남았다. 이는 aggregate runner의 ``후속 단계 계속 실행`` 동작 증거일 뿐 전체 수용 PASS 증거는 아니다.

두 번째 시도는 다른 `APPDATA`/`LOCALAPPDATA` user-data root와 다른 로그 디렉터리를 사용해 단일 background PowerShell에서 실행했다. `campaign-locked-100` 자식은 시작 뒤 110초를 넘겨 진행 출력 없이 정지했으므로, 오케스트레이터 지시에 따라 PID 51520과 부모 PID 24040을 종료했다. 이 실행은 의도적 음성 시험이 아니며, 작업 트리나 정본 fixture는 변경하지 않았다.

## 깨끗한 worktree 재현 (오케스트레이터)

`b184fc7`에서 `out/q05-clean` detached worktree를 만든 뒤 동일 실행기를 단독 실행했다. import는 exit 0이었지만, 아직 완료되지 않은 Godot cache 때문에 단위시험의 P0-04 초상 섹션이 23건 실패했다. 결과는 35/35 섹션, 690 단언(하한 701), exit 1이다. Q-06-01에서 해당 원본 폰트·PNG가 모두 Git 추적임을 확인했고, 두 pass import/cache 준비 뒤 단위시험 35/35·701/0으로 정상화했다.

같은 깨끗한 실행의 `campaign-locked-100`은 배너 뒤 중간 출력이 없었고 110초에 중단됐다. Q-06-01은 이를 hang이 아니라 400회 전체 실행의 미완료 관찰로 정정했다. 따라서 현재 판정은 **PARTIAL/미수용**이며, 교정 HEAD에서 격리된 전체 gate aggregate 0과 나머지 음성 항목, 원격 workflow 결과를 실제 값으로 채워야 PASS로 변경한다.

## 원격 상태

Workflow를 포함한 commit `d947d2ed23abf1d418a7660f4033290d848763eb`은 `origin/main`에 push했다. 이 환경에서는 GitHub Actions 실행 목록을 조회할 인증/네트워크 경로를 확인하지 못했으므로 run URL·job 결과는 **미확인**이다. 원격 PASS를 추정하지 않으며, 새 clone 실패가 이미 확인되어 원격 수용도 PARTIAL이다.
