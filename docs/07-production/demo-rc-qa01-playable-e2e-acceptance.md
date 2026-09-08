# DEMO-RC-QA-01 — 적벽대전 플레이어블 데모 E2E 독립 수용

검수일: 2026-09-08
검수 방식: 구현 비변경 독립 검수 (Windows headless Godot 4.7.2)

## 판정

**PARTIAL (렌더·저장 수용 PASS, OS 물리 입력 수용 보류).** 수정 후 실제 `Main` 제품 경로를 거치는 전용 E2E가 0 failures로 통과했고, 기존 전투 진입 셸 시험과 DEMO-RC-03/04 구조 시험도 다시 통과했다. GUI Godot 렌더러가 제품 viewport를 1600×900으로 실제 렌더해 6개 PNG를 생성했고, 분리된 writable user-data 경로에서 파일 저장·복원도 73/0으로 통과했다. 다만 현 Computer Use 표면은 Godot 네이티브 창의 물리 마우스/키보드를 노출하지 않아 OS-level 입력 수용만 별도 Windows 표면에서 남는다.

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
| 파일 저장·복원 | `run_save_restore.gd` + writable `--user-data-dir` | PASS — 73 pass, 2 skip, 0 fail |
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

### 해결됨 — 파일 저장/복원 E2E

기본 샌드박스의 `user://`는 파일을 쓰지 못했으나, 프로젝트 내부 `out/demo-rc-qa01-playable-e2e/user-data`를 Godot `--user-data-dir`로 명시한 unrestricted acceptance 실행에서는 저장·복원이 정상 동작했다.

```
Failed to open 'user://logs/godot...log'
Failed to open log file for writing: user://logs/godot.log
```

`tests/run_save_restore.gd`의 stale future-ruleset fixture도 `RS-0.6.0`으로 올려 현재 `RS-0.5.0` 규칙 세대와 일치시켰다. 최종 결과는 **73 pass · 2 skip · 0 fail**이다.

## Windows 1600x900 GUI 검수

Godot GUI(`Godot_v4.7.2-stable_win64.exe --path .`)를 안전하게 기동했고 프로세스가 실행 중임을 확인했다. 그러나 이 검수 세션의 Computer Use 표면은 Edge 브라우저만 노출하고 네이티브 앱 목록은 비어 있어, Godot 창의 화면 캡처·마우스/키보드 입력을 획득할 수 없었다. 검수자가 기동한 GUI 프로세스는 확인 뒤 종료했다.

GUI executable에서 `tests/capture_demo_rc_gui.gd`를 실행해 다음 제품 viewport 캡처를 생성했다. 모두 **1600×900 PNG**이며 `out/`에만 둔다.

| 파일 | 바이트 | SHA-256 |
|---|---:|---|
| `01-demo-entry-1600x900.png` | 1,070,537 | `2DE60288220FD0F5A067D8D01A5B66BE573B6A0F856A9A5E6C47AB6695B9C71B` |
| `02-phase-1-contact-1600x900.png` | 441,893 | `8085F4675C5099CD920704D00EBADEDFBF16F1F40EB040C1137C1FC35EEBF301` |
| `03-phase-2-barrage-1600x900.png` | 443,502 | `41F6D09A7053B98352E4A12C7170191B2CD1FA9E8DC6663C05AAE5EF94E41C46` |
| `04-phase-4-assault-1600x900.png` | 449,000 | `CEB183E8B07A11BBE41D09E43A62D31D33BFBD34A9431D3CCEE5391B69B73012` |
| `05-resolution-1600x900.png` | 454,423 | `3B1132AB40421B6C0D7B81961731BC74BC8E9F1355C356891DF8BE71F505DDEA` |
| `06-return-home-1600x900.png` | 1,070,458 | `E0F912AD4D02793A2D8DB17DD06594D161A7CC95B77BFFE19D3551A9E2B05CE7` |

캡처는 2/3 전술 지도·1/3 procedural 전장, 한글 UI, 페이즈 갱신 및 결과/홈 복귀를 확인한다. 다음 항목은 여전히 **NOT VERIFIED**다.

- OS 물리 마우스/키보드로 전투 버튼을 누르는 수용

## 검수 결론

DEMO-RC-01~05의 제품 흐름, GUI renderer 1600×900 캡처, 파일 저장·복원은 PASS다. OS-level 물리 입력 표면 하나만 현 세션에서 제공되지 않았으므로, 전체 `DEMO-RC-QA-01`은 **PARTIAL**로 유지한다.
