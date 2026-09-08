# DEMO-RC-QA-01 — 적벽대전 플레이어블 데모 E2E 독립 수용

검수일: 2026-09-08
검수 방식: 구현 비변경 독립 검수 (Windows headless Godot 4.7.2)

## 판정

**PARTIAL (자동 E2E PASS, Windows 실화면 수용 보류).** 수정 후 실제 `Main` 제품 경로를 거치는 전용 E2E가 0 failures로 통과했고, 기존 전투 진입 셸 시험과 DEMO-RC-03/04 구조 시험도 다시 통과했다. 다만 현 검수 환경은 `user://` 파일 쓰기와 네이티브 Godot 창 캡처/입력 표면을 제공하지 않아, 파일 기반 복원 및 1600x900 실제 GPU 시각·입력 수용은 완료할 수 없다.

## 자동 검수 결과

| 범위 | 명령 | 결과 |
|---|---|---|
| DEMO-RC-01 진입 | `test_demo_rc_01_playable_entry.gd` | PASS — 9/9 |
| DEMO-RC-03/04 화면 구조 | `test_demo_rc_03_04.gd` | PASS — 0 failures |
| DEMO-RC-QA-01 제품 E2E (수정 후) | `test_demo_rc_qa01_e2e.gd` | PASS — 0 failures |
| 기존 전투 진입 셸 (수정 후) | `test_red_cliff_battle_entry_shell.gd` | PASS — 33/33 |
| 5페이즈·결과·재생 | `test_scn03_red_cliff_phase_result.gd` | PASS — 44/44 |
| 기존 적벽 진입 E2E | `test_g10_qa01_red_cliffs_entry_e2e.gd` | assertions PASS — 24/24, 단 화면 런타임 오류 있음 |
| A-05 진형 코어 | `test_a05_formation_combat.gd` | PASS — 93/93 |
| 전체 코어 | `run_tests.gd` | PASS — 701/701 |
| SCN-03 진행 저장/재생 | `test_scn03_progress_save_replay.gd` | PASS — 40/40 |
| 파일 저장·복원 | `run_save_restore.gd` | FAIL — 52 pass, 2 skip, 5 fail |
| 캠페인 파일 재생 | `run_campaign_replay.gd` | FAIL — 25 pass, 1 fail |

`run_campaign.gd` 및 `q01_scheme_sensitivity.gd`는 약 90초 동안 결과 출력 없이 유휴 상태인 새 콘솔 프로세스로 남아, 검수자가 시작한 PID만 종료했다. 따라서 이 두 장기 배치 시험은 **미완료**로 기록한다. 기존 10:37 시작 콘솔 PID는 소유권 불명으로 보존했다.

## 주요 결함

### 해결됨 — Main 통합 전투 화면의 ActiveBattle 동적 접근

- 재현: `Godot --headless --path . --script tests/test_g10_qa01_red_cliffs_entry_e2e.gd`
- 이전 결과: assertions는 24/24 통과하지만, 전투 배너를 눌러 `Main._open_red_cliff_battle_entry_shell()`이 `RedCliffBattleView.configure()`를 호출하면 매 refresh마다 아래 오류가 발생했다.

```
Invalid call to function 'get' in base 'RefCounted (ActiveBattle)'. Expected 1 argument(s).
```

- 수정 확인: 현재 [scripts/RedCliffBattleView.gd](../../scripts/RedCliffBattleView.gd) 72–77행은 `battle.combat_phase`, `battle.attacker_ships`, `battle.defender_ships`, `battle.attacker_morale`, `battle.defender_morale`의 명시적 속성 접근으로 교체됐다. `battle.result`만 Dictionary이므로 `.get("winner_faction_id", "")`를 사용한다.
- 재검수: `test_demo_rc_03_04.gd` 0 failures, `test_demo_rc_qa01_e2e.gd` 0 failures, `test_red_cliff_battle_entry_shell.gd` 33/33 통과. 세 출력에 이전 `Invalid call to function 'get' in base 'RefCounted (ActiveBattle)'` 오류가 없었다.

### P1 — 파일 저장/복원 E2E가 이 검수 환경에서 실패

`run_save_restore.gd`와 `run_campaign_replay.gd`는 `user://` 파일을 쓰지 못했다. 공통 선행 오류는 다음과 같다.

```
Failed to open 'user://logs/godot...log'
Failed to open log file for writing: user://logs/godot.log
```

이후 `파일 저장` 실패, `corrupt != ok`, nil 대상 `run_to_end`/`digest` 오류로 이어졌다. 메모리 기반 적벽 저장·복원(`test_scn03_red_cliff_phase_result.gd`)은 통과했으나, 요구된 실제 저장 후 게임 상태 재구성 수용은 별도 쓰기 가능한 Windows 사용자 경로에서 다시 검증해야 한다.

## Windows 1600x900 GUI 검수

Godot GUI(`Godot_v4.7.2-stable_win64.exe --path .`)를 안전하게 기동했고 프로세스가 실행 중임을 확인했다. 그러나 이 검수 세션의 Computer Use 표면은 Edge 브라우저만 노출하고 네이티브 앱 목록은 비어 있어, Godot 창의 화면 캡처·마우스/키보드 입력을 획득할 수 없었다. 검수자가 기동한 GUI 프로세스는 확인 뒤 종료했다.

따라서 `out/demo-rc-qa01-playable-e2e/`에는 수용 가능한 실제 캡처가 생성되지 않았다. 다음 항목은 **NOT VERIFIED**다.

- 실제 GPU 1600x900 레이아웃, 한글 글리프, 버튼 크기/잘림
- 전술 지도 약 2/3 및 3D 증거창 약 1/3의 실제 렌더링
- 전투 버튼의 실제 입력과 중복 클릭 방지
- 5개 이상 화면 캡처 및 SHA-256

## 검수 결론

DEMO-RC-01~05의 메모리 기반 제품 흐름은 수정 후 E2E로 확인됐다. 따라서 자동화 범위에서는 PASS다. 그러나 파일 기반 `user://` 저장 재구성과 네이티브 창을 캡처할 수 있는 1600x900 Windows GPU GUI 재검수가 남아 있으므로, 전체 `DEMO-RC-QA-01 PASS`가 아닌 **PARTIAL**로 판정한다.
