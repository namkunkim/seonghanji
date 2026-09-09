# DEMO-RC-QA-03 — 적벽대전 전체 시나리오·엔딩 루프 수용

## 대상

DEMO-RC-LT-02는 기존 DEMO-RC-01~05 전투 수직 슬라이스의 앞뒤를 연결한다.
검수는 `scenario-200-208.md` Event 03/04/06/07·Event 09, `endings.md` §5.2의
DEC-01, 기능 이벤트·저장 계약을 기준으로 한다. UI가 canonical Campaign 상태를
읽는지, 공개 명령만 발행하는지를 우선 검사한다.

## 자동 수용표

| 범주 | 명령 | 필수 관찰 | 종료 |
|---|---|---|---|
| LT-02 코어 | `godot --headless --path . --script tests/test_demo_rc_lt02_campaign_loop.gd` | 선택 one-shot, 발생 결정성·저장/복원, 공개 activation·재호출 거부, DEC-01·저장/복원 | **38/0, exit 0** |
| 기존 진입 | `godot --headless --path . --script tests/test_demo_rc_01_playable_entry.gd` | 브리핑→선택→pending→active, canonical ID, 개전 뉴스 exactly-once, 저장/복원, 새 시작 격리 | **15/0, exit 0** |
| 기존 전투·결과 | `godot --headless --path . --script tests/test_demo_rc_03_04.gd` 및 `godot --headless --path . --script tests/test_demo_rc_qa01_e2e.gd` | 5페이즈·결과 exactly-once·결과 브리핑·홈 복귀·resolved 재진입 거부 | **03/04 0 failures; QA-01 40/0, 각각 exit 0** |
| 입력 회귀 | `godot --path . --script tests/test_demo_rc_qa02_native_input.gd` | 키보드·마우스 제품 입력, 명령 경계 | **보류:** Intel Arc 130V Vulkan 창 기동은 확인했으나 반복 GUI 실행에서 브리핑 mount 관찰이 실패했다. headless dummy renderer는 texture capture가 불가하다. |
| 기존 수직 슬라이스 | `godot --headless --path . --script tests/test_g10_qa01_red_cliffs_entry_e2e.gd` | 조건→뉴스/active→전투 셸→홈 | 0 |
| 형성·저장·재생 | `godot --headless --path . --script tests/test_a05_formation_combat.gd`; `tests/run_save_restore.gd`; `tests/run_campaign_replay.gd` | 기존 5페이즈 진형, 파일 저장/복원, 명령 로그 digest | 각각 0 |
| 전체 회귀 | `godot --headless --path . --script tests/run_tests.gd` | 기존 모든 섹션 및 assertion 하한 | **환경 기존 실패:** `user://` 저장 거부 뒤 698<701 하한, exit 1. LT-02 변경과 분리되어 있으며 완화하지 않았다. |

Windows Godot 4.7.2 console에서 LT-02 코어는 **38 통과·0 실패·exit 0**을 확인했다.
나머지 PASS 수치는 구현 후 같은 HEAD에서 실제 출력으로만 채운다.

## 수동 GPU 수용

Windows 1600×900 Vulkan Forward+에서 다음을 하나의 새 데모와 하나의 미발생 데모로
확인한다.

1. 홈 `적벽` → 브리핑의 네 선택은 순서대로 한 번만 확정되며, 이미 확정한 선택은 다시 눌러도 상태를 바꾸지 않는다.
2. 다섯 true 선택은 canonical active 전투로 이어지고, 기존 5페이즈가 끝난 뒤 결과 브리핑과 홈 복귀가 가능하다.
3. false 전제는 `DEC-01: 적벽 미발생` 브리핑으로 가며 battle marker/셸을 만들지 않는다.
4. 홈의 이어하기는 같은 canonical 상태를 읽고, 새 데모는 브리핑부터 새 Campaign으로 시작한다.
5. resolved 전투 셸 재진입은 거부되고, Tab/Enter와 마우스 모두로 브리핑·홈 조작이 가능하며 잘림·포커스 함정이 없다.

Win32 SendInput 또는 실제 장치 주입을 이 자동화 환경에서 직접 검증할 수 없으면, 그 한 항목은 출시 전 사람 스모크로 분리 기록한다.
