# DEMO-RC-FIN QA 실행 증거

> 마감 시 보존한 중간 QA 기록이다. 아래 ‘아직 미실행’ 등의 문장은 기록 당시 상태이며, 최종 run33 및 후보 해시 판단은 [마감 기술 감사](demo-rc-final-technical-audit.md)를 우선한다. 과거 시험과 해시를 현재 후보로 조용히 치환하지 않는다.

> 기준: `demo-rc-completion-review-checklist.md` G1·G2·G9 · 2026-09-10 · 상태: 진행 중, 최종 수용 아님

## 후보와 환경

- 통합 출발 커밋: `111d0f2a6e8cfbf98000ae3a88eefcfc60296bd5`.
- 이 기록은 미커밋 통합 후보의 지정 파일 해시를 함께 고정한다. 전체 worktree에는 코어·UI 변경 및 Godot import 산출물이 공존하므로, 커밋 SHA만으로 후보를 식별하지 않는다.
- 엔진: `Godot_v4.7.2-stable_win64_console.exe`, 출력 버전 `4.7.2.stable.official.ed1daf0bf`.
- 각 시험은 별도 `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-0N\user-data`를 `APPDATA`, `LOCALAPPDATA`, `USERPROFILE`에 지정했다. 실행 후 모두 `Godot\app_userdata\SEONGHANJI- MANDATE\logs`를 만들었으므로 `user://`가 기존 사용자 저장소가 아닌 해당 경로에 격리됐음을 확인했다.
- 모든 로그에는 Windows 루트 인증서 저장소를 읽지 못했다는 Godot 진단이 한 줄 포함된다. 아래 시험의 자체 종료 코드와 단언 결과는 0/PASS이며 인증서 경고는 판정 실패가 아니다.

## G2·LT-03 집중 실행

공통 실행 형식은 다음과 같다. 각 행의 `N`과 시험 파일만 바꿨다.

```powershell
$runRoot = 'C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-0N'
$userData = Join-Path $runRoot 'user-data'
$logDir = Join-Path $runRoot 'logs'
New-Item -ItemType Directory -Force -Path $userData,$logDir | Out-Null
$env:APPDATA = $userData; $env:LOCALAPPDATA = $userData; $env:USERPROFILE = $userData
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/<test>.gd
```

| N | 시험 | 결과 | 종료 코드 | 로그 |
| --- | --- | --- | --- | --- |
| 01 | `test_demo_rc_fin_player_authority.gd` | 54 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-01\logs\test_demo_rc_fin_player_authority.log` |
| 02 | `test_red_cliff_command_feedback.gd` | 0 failures | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-02\logs\test_red_cliff_command_feedback.log` |
| 03 | `test_demo_rc_lt03_deployment_core.gd` | 55 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-03\logs\test_demo_rc_lt03_deployment_core.log` |
| 04 | `test_scn03_red_cliff_manifest_activation.gd` | 73 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-04\logs\test_scn03_red_cliff_manifest_activation.log` |
| 05 | `test_scn03_progress_save_replay.gd` | 40 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-05\logs\test_scn03_progress_save_replay.log` |
| 06 | `test_demo_rc_qa03_full_scenario_loop.gd` | **BLOCKED** — `scripts/Main.gd` parse error at lines 1133 and 1432; UI coroutine never ran | 0 (invalid as PASS) | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-06\logs\test_demo_rc_qa03_full_scenario_loop.log` |

각 실행의 명시적 종료 코드는 같은 `logs` 폴더의 `*.exitcode.txt`에 보존했다.

## UI 후보 집중 실행

| N | 시험 | 결과 | 종료 코드 | 로그 |
| --- | --- | --- | --- | --- |
| 06 | `test_demo_rc_qa03_full_scenario_loop.gd` | **무효** — `Main.gd` parse error로 UI 경로 미기동 | 0 (무효) | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-06\logs\test_demo_rc_qa03_full_scenario_loop.log` |
| 07 | `test_demo_rc_qa03_full_scenario_loop.gd` | 95 passed / 1 failed — 새 체험판 제목 계약 차이 | 1 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-07\logs\test_demo_rc_qa03_full_scenario_loop.log` |
| 08 | `test_demo_rc_qa03_full_scenario_loop.gd` | 96 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-08\logs\test_demo_rc_qa03_full_scenario_loop.log` |
| 09 | `test_demo_rc_qa04_manual_deployment_loop.gd` | 33 passed / 0 failed; headless라 PNG 캡처는 의도적으로 defer | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-09\logs\test_demo_rc_qa04_manual_deployment_loop.log` |
| 10 | `test_demo_rc_qa01_e2e.gd` | 0 passed / 1 failed — 진형 후보의 하드코딩된 이름 기대 | 1 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-10\logs\test_demo_rc_qa01_e2e.log` |
| 11 | `test_demo_rc_qa01_e2e.gd` | 0 failures | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-11\logs\test_demo_rc_qa01_e2e.log` |
| 12 | `test_demo_rc_fin_save_load_ui.gd` | **무효** — 새 시험의 `saved_digest` type-inference parse error | 1 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-12\logs\test_demo_rc_fin_save_load_ui.log` |
| 13 | `test_demo_rc_fin_save_load_ui.gd` | 15 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-13\logs\test_demo_rc_fin_save_load_ui.log` |
| 14 | `test_demo_rc_qa02_native_input.gd` | 24 passed / 9 failed — headless dummy renderer framebuffer 부재, 그리고 구 x1 시간 가정 | 1 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-14\logs\test_demo_rc_qa02_native_input.log` |
| 15 | `test_demo_rc_qa02_native_input.gd` | 26 passed / 2 failed — capture를 GPU 수용으로 defer한 뒤, 5국면 전체가 4x에서 약 75초임을 확인 | 1 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-15\logs\test_demo_rc_qa02_native_input.log` |
| 16 | `test_demo_rc_qa02_native_input.gd` | 28 passed / 0 failed; mouse/keyboard `Input.parse_input_event`으로 전투 진입·명령·AI 위임·첫 AI 국면 확인, GPU capture 6건 defer | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-16\logs\test_demo_rc_qa02_native_input.log` |

08·09·11·13은 각자 새 격리 user-data를 사용했다. 13은 가시 top 저장/이어하기 경로, `SaveSlotOne`/`LoadSlotOne`, 실제 `user://demo-rc-slot-1.json`, 저장 digest 복원 및 로드 후 일시정지를 검증한다.

## 파일 해시

| 파일 | SHA-256 |
| --- | --- |
| `core/campaign.gd` | `5EBF83E3347AE4F8F5D97A27F1FFA268E3FCBEBA8F0769C1E3BAB90978FE1082` |
| `core/save.gd` | `158462759BD3FC2C6E5BE03F29720A93F6494DCD2EBE37BE94F1FF1C7CD2BAC1` |
| `tests/test_demo_rc_fin_player_authority.gd` | `BA8CA1A083EF6292179F2EE591FA43F03FAD9E892B388076B859755320163FF3` |
| `tests/test_red_cliff_command_feedback.gd` | `D9673F4848200124E27F633D3AFE4B6BB3C7908535520E249262EF93AA1AA41B` |
| `tests/test_demo_rc_lt03_deployment_core.gd` | `87898DC99B39EFFBA0B8074CB71AE6D201110572A4C84C3F9B2A6FF9D87322A9` |
| `tests/test_scn03_red_cliff_manifest_activation.gd` | `8318971CA4D1A62B3FB8BE5FA61D26E6DE678FC6F639B0BDD944F625432DF11E` |
| `tests/test_scn03_progress_save_replay.gd` | `3EB9DACD5A8E9D04DE69E14614F0BA843ECDD1BE136DA9C53EFEC84CF66F7346` |

### UI 집중 후보 해시

| 파일 | SHA-256 |
| --- | --- |
| `scripts/Main.gd` | `BE949058B80DF41A35E8211D36EF955AEAC1A4F097FA4781DE08CC88B34953BA` |
| `scripts/RedCliffBattleView.gd` | `8CE0D0CE09857748FCAD31D195AAC722C46B85955255BFDF133621DDE82061FA` |
| `app/home_map_snapshot.gd` | `B74FE9C17EB1B8B46BF6C1317E5DED8A0ED4B0B7148ABA012452F49E7A941C78` |
| `tests/test_demo_rc_qa01_e2e.gd` | `81F1DD7FCE0BD5E7E4175C0D26A0DE805211367614E0AA6ED4331D62C0E34030` |
| `tests/test_demo_rc_qa03_full_scenario_loop.gd` | `AE33EFB278C1283DC4CE13DC1D0DB8598D03E6465A21A9E9F4AB782D75622842` |
| `tests/test_demo_rc_qa04_manual_deployment_loop.gd` | `8EAC60FEEB009008D1CAC54C7CEB3CBD8E7DEB761B0FDD295AEE865E8A444E9F` |
| `tests/test_demo_rc_qa02_native_input.gd` | `8E4676FE4EEC0DCE98EB96D77A3F7DEF6C243CA6BE67A7F558DB82D442845972` |
| `tests/test_demo_rc_fin_save_load_ui.gd` | `804304C3F8E4140A74202F9957AE6A0F19450F5811110F895488825367EF689C` |
| `tools/ci/run_quality_gate.ps1` | `A1D0DCCF928AE63BC2CF3D35F37E03AE5FB7B3AF712C9FC23EA663DA2DD7824D` |

## 판정 범위와 잔여

## 보강 후 재검증 (후속 후보)

| N | 시험 | 결과 | 종료 코드 | 로그 |
| --- | --- | --- | --- | --- |
| 17 | `test_demo_rc_g8_accessibility_audio.gd` | 16 passed / 0 failed | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-17\logs\test_demo_rc_g8_accessibility_audio.log` |
| 25 | `test_demo_rc_qa01_e2e.gd` | 0 failures — 결과 재열람·새 체험 경계 포함 | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-25\logs\test_demo_rc_qa01_e2e.log` |
| 29 | `test_demo_rc_qa03_full_scenario_loop.gd` | 107 passed / 0 failed — 실제 demo profile/45틱/restore 포함 | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-29\logs\test_demo_rc_qa03_full_scenario_loop.log` |
| 31 | `test_demo_rc_lt02_campaign_loop.gd` | 38 passed / 0 failed — 현재 manifest·수동 집결 계약 | 0 | `C:\WorkSpace\Seonghanji\tmp\demo-rc-fin-qa-run-20260910-31\logs\test_demo_rc_lt02_campaign_loop.log` |

`run18/quality-gate/summary.json`은 전체 기준선의 stage별 로그를 남겼으나, 당시 LT-02 parse failure와 사람이 끊은 동기 importer 이력이 있으므로 최종 PASS 증거가 아니다. `run_quality_gate.ps1`은 이후 동기 `--editor --quit`을 제거하고 timeout-bounded importer와 `SCRIPT ERROR`/`Parse Error` exit-0 승격을 추가했다. 후속 후보는 이 새 runner로 전체 gate를 다시 실행해야 한다.

- 위 결과는 코어 권한, 새 `player_side:defender` 명령 무결성, side-less legacy 명령 재생 모양, 수동 집결 및 manifest 활성화의 headless 집중 증거다.
- 실제 이전 빌드에서 보관된 save fixture는 작업공간에 없으므로, legacy 검증은 시험이 구성한 side-less 과거 payload의 재생 증거이며 과거 후보 파일 자체의 호환 증거는 아니다.
- UI 후보 첫 실행은 06에서 차단됐다. Godot는 `Main.gd`의 type-inference parse error 뒤에도 이 비동기 시험 프로세스에 0을 돌려주었으므로, 출력의 `73/0`은 UI 제품 경로 증거가 아니며 PASS로 기록하지 않는다. 08에서 실제 제품 흐름을 재검증했다.
- QA-02는 headless에서 Godot public mouse/keyboard event 경로와 첫 AI 위임 국면까지 28/0으로 실행했다. 이는 Windows OS 물리 입력도, GPU framebuffer도 아니다. 더미 renderer가 framebuffer texture를 제공하지 않아 6개 PNG/1600×900 capture는 명시적으로 defer했다.
- 문서화된 4x 속도에서 한 틱은 15초, 5국면 완결은 약 75초다. QA-02는 이를 가속하지 않고 첫 AI 국면만 확인한다. 실제 4x 완결 시간과 인간 관찰은 자동 PASS가 아니다.
- 전체 quality gate는 이 후보에 아직 실행하지 않았다.
- 최초 사용자 관찰, 물리 입력, export 패키지 실행 및 Windows export template 검증은 미수용이다.

## 검토 포인트

1. export template 설치 여부와 실제 패키지 해시를 별도 G10 기록으로 연결한다.
2. GPU renderer에서 1600×900 PNG 및 OS 키보드·마우스 스모크를 사람이 검수한다.
3. 실제 4x의 완결 시간과 최초 사용자 관찰을 자동 PASS로 대체하지 않는다.
