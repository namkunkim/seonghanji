# DEMO-RC-QA-01 — 적벽대전 플레이어블 데모 E2E 독립 수용

검수일: 2026-09-08~09
검수 방식: 독립 자동 검수 + Windows 네이티브 GPU 입력 수용

## 판정

**PASS — 제품 E2E 및 Godot 공개 입력 경로.** 실제 `Main` 제품 경로 E2E, 5페이즈·결과·저장·재생과 코어 회귀가 통과했다. Windows 비콘솔 Godot는 Intel Arc GPU에서 1600×900 제품 화면을 렌더했고, `DEMO-RC-QA-02`가 화면 좌표 마우스와 Tab/Enter 키보드 입력으로 시작부터 결과·홈 복귀까지 47/47을 통과했다. 이 판정은 Win32 `SendInput` 또는 물리 장치 시험을 뜻하지 않으며 그 항목은 출시 전 사람 스모크로 남긴다.

## 자동 검수 결과

| 범위 | 명령 | 결과 |
|---|---|---|
| DEMO-RC-01 진입 | `test_demo_rc_01_playable_entry.gd` | PASS — 9/9 |
| DEMO-RC-03/04 화면 구조 | `test_demo_rc_03_04.gd` | PASS — 0 failures |
| DEMO-RC-QA-01 제품 E2E (수정 후) | `test_demo_rc_qa01_e2e.gd` | PASS — 0 failures |
| 기존 전투 진입 셸 (수정 후) | `test_red_cliff_battle_entry_shell.gd` | PASS — 33/33 |
| 5페이즈·결과·재생 | `test_scn03_red_cliff_phase_result.gd` | PASS — 46/46 |
| 명령 거부·결착 근거 | `test_red_cliff_command_feedback.gd` | PASS — 0 failures |
| 기존 적벽 진입 E2E | `test_g10_qa01_red_cliffs_entry_e2e.gd` | PASS — 24/24, 화면 런타임 오류 없음 |
| A-05 진형 코어 | `test_a05_formation_combat.gd` | PASS — 93/93 |
| 전체 코어 | `run_tests.gd` | PASS — 701/701 |
| SCN-03 진행 저장/재생 | `test_scn03_progress_save_replay.gd` | PASS — 40/40 |
| 파일 저장·복원 | `run_save_restore.gd` + writable `APPDATA`/`LOCALAPPDATA` | PASS — 73 pass, 2 skip, 0 fail |
| 캠페인 파일 재생 | `run_campaign_replay.gd` + writable `APPDATA`/`LOCALAPPDATA` | PASS — 29/29, exit 0 |
| 장기 캠페인 잠금 회귀 | `run_campaign.gd` | PASS — 400/400, exit 0, 588초 |
| Q-01 HB 감도 | `q01_scheme_sensitivity.gd` | PASS — 500/500, exit 0, 약 600초 |
| Windows GPU 공개 입력 경로 | `test_demo_rc_qa02_native_input.gd` | PASS — 47/47, mouse + keyboard |

`run_campaign.gd` 및 `q01_scheme_sensitivity.gd`의 무출력 구간은 교착이 아니다. 전자는 표준 100회와 HB 비교 3×100회를, 후자는 HB 5모드×100회를 진행하고 각 100회 묶음이 끝날 때만 출력한다. 2026-09-09 단독 재실행에서 두 시험은 모두 exit 0으로 완주했다.

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

기본 샌드박스의 `user://`는 파일을 쓰지 못했으나, 프로젝트 내부 폴더를 `APPDATA`와 `LOCALAPPDATA`로 지정한 acceptance 실행에서는 저장·복원이 정상 동작했다. Godot 4.7 Windows에는 `--user-data-dir` 플래그를 사용하지 않는다.

```
Failed to open 'user://logs/godot...log'
Failed to open log file for writing: user://logs/godot.log
```

`tests/run_save_restore.gd`의 stale future-ruleset fixture도 `RS-0.6.0`으로 올려 현재 `RS-0.5.0` 규칙 세대와 일치시켰다. 최종 결과는 **73 pass · 2 skip · 0 fail**이다.

### 환경 한계 — 기본 sandbox의 `run_campaign_replay.gd` 파일 왕복

2026-09-09 기본 sandbox에서 `--log-file out/demo-rc-qa01-playable-e2e/run_campaign_replay.log`로 로그 위치만 workspace로 돌려 단독 재실행했다. 결과는 **25 pass · 1 fail · exit 1**이었다. `Campaign.write_save("user://test_campaign_save.json")`가 false를 반환했고, 당시 테스트는 뒤이어 null `Campaign`의 `digest()`까지 호출했다.

이는 제품 재생/지문 오류가 아니다. 이 실행 계정의 `C:\Users\nk782\AppData\Roaming\Godot\app_userdata\SEONGHANJI- MANDATE` ACL은 `CodexSandboxUsers`에 `ReadAndExecute`만 부여한다. 따라서 Godot `FileAccess.open(user://..., WRITE)`가 실패한다. 프로젝트 내부 폴더를 `APPDATA`·`LOCALAPPDATA`로 지정해 재실행한 최종 수용은 **29/29 · exit 0**, 2160틱 재생 평균 **1545ms**로 통과했다.

테스트 보고 경로도 보강했다. `write_save()` 실패 또는 null 복원 시 즉시 해당 단언만 실패시키고 반환하므로, ACL 오류가 후속 `digest()` null 호출로 중복 보고되지 않는다. 제품 코드와 Q-01 상수는 변경하지 않았다.

### 장기 회귀 재실행 — 완료 시간과 잠금값

- `run_campaign.gd`: **588초**, 400/400 완주, exit 0. 표준 100회 잠금값은 역사 재현율 **60.0%**, 조기 종료율 **0.0%**, 주역 세력 편차 **1.3배**(잠금 3/3 통과). HB 비교는 자유 63.0%/0.0%, 표준 60.0%/0.0%, 역사 중시 66.0%/0.0%(각각 재현율/일극형)였다.
- `q01_scheme_sensitivity.gd`: 약 **600초**, 500/500 완주, exit 0. `HB 0.00/0.10/0.15/0.20/0.25`의 `(역사, 조기, 조조, 손권, 유종, 편차, 이벤트)`는 각각 `(63,0,27,28,45,1.7,17)`, `(70,0,21,37,57,2.7,17)`, `(69,0,25,33,42,1.7,17)`, `(81,0,19,40,50,2.6,16)`, `(60,0,35,34,44,1.3,17)` 퍼센트/배/종이다.

## Windows 1600x900 GUI 검수

Godot GUI를 Vulkan Forward+ / Intel Arc 130V 8GB에서 실행했다. `tests/test_demo_rc_qa02_native_input.gd`는 제품 `Main`에 화면 좌표 마우스 press/release와 Tab/Enter 키보드 이벤트를 전달해 전 흐름을 47/47로 완료했다. 세부 경계와 캡처는 `demo-rc-qa02-windows-native-input-acceptance.md`에 기록한다.

GUI executable에서 `tests/capture_demo_rc_gui.gd`를 실행해 다음 제품 viewport 캡처를 생성했다. 모두 **1600×900 PNG**이며 `out/`에만 둔다.

| 파일 | 바이트 | SHA-256 |
|---|---:|---|
| `01-demo-entry-1600x900.png` | 1,070,667 | `676E8A1A130E3E3CA6E5E30ABC75A0BF60D0B47E9B6038C3E37EB3189A6C71ED` |
| `02-phase-1-contact-1600x900.png` | 571,896 | `14FB0759D660A2D3EB0821806D2F6E931B4E5086EFD66E5388D66A08E23315E1` |
| `03-phase-2-barrage-1600x900.png` | 582,237 | `2A152AAC57B8E399BF079F21F31214C5839ADBC4C12E22DB878EBC7F26FCBEFB` |
| `03a-selected-fleet-1600x900.png` | 590,633 | `9933AEF592B5E5F56D13733883AC40B21168062F976B81C54FCA6DB0686B686E` |
| `03b-formation-comparison-1600x900.png` | 419,104 | `AF377B279A794FA92228F64DF5B5CC263552B1791797E8251C24472AB808F734` |
| `03c-battle-history-1600x900.png` | 423,058 | `CD3B222194175E7DC6A8B03A4F44D0357FCF11AE64230B13290F6A13EA1AA835` |
| `04-phase-4-assault-1600x900.png` | 587,360 | `BF2563E89BD712723D28F10A398F624F5AED3336ACED352338845A734DB95879` |
| `05-resolution-1600x900.png` | 552,910 | `A3583D4F38354313C5A5608AC865D1DD475D2A6A329515EAB64E1BD244E667D7` |
| `06-return-home-1600x900.png` | 1,070,442 | `0758DD34BFBEE456DDE4BCAB86D27A67A41D144A5D8DF60EEF196F637562FF0A` |

캡처는 2/3 전술 지도·1/3 정지 전투 이미지, 한글 UI, 페이즈 전과 연출, 함대 선택, 진형 비교, 누적 기록, 결착 근거 및 홈 복귀를 확인한다. 2026-09-09 발주자 지시에 따라 실시간 3D는 별도 지시 전까지 정지 이미지 한 장으로 대체한다. Computer Use가 네이티브 앱을 노출하지 않아 Windows 하드웨어 SendInput은 자동화하지 못했으며, 동일 제품 창의 공개 Godot 입력 이벤트 경로를 수용했다.

## 검수 결론

DEMO-RC-01~05의 제품 흐름, 정지 이미지 정책의 전투 화면, GUI renderer 1600×900 캡처, Godot 공개 마우스·키보드 입력, 파일 저장·복원·재생과 코어 회귀를 수용했다. 전체 `DEMO-RC-QA-01`은 이 범위에서 **PASS**이며 Windows 물리 장치 입력만 출시 전 사람 스모크로 남는다.
