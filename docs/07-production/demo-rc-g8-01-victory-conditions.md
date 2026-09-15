# DEMO-RC-G8-01 — 매 턴 기본 승리 조건 판정

## 범위

전투 효과가 확정한 `victory_inputs`를 각 턴의 resolution 직후 결정론적으로 판정한다. 이 단계는 비용 손실과 전대 사기 항복으로 만들 수 있는 기본 종료만 확정한다. 기함 격침·탈출점·20턴 잔존비 비교는 위치와 기함 의미를 함께 소비해야 하므로 G8-03에 남긴다. 장수 casualty도 계속 pending이다.

## 규칙과 우선순위

`data/red-cliffs-victory-rules.json`의 `normal-demo-victory-v1`이 정본이다.

- 세력의 현재 composition 비용을 immutable original composition 비용과 비교한다. 손실이 7000bp 이상이면 해당 세력은 패배 조건을 충족한다.
- 모든 전대가 `surrendered`이면 비용과 무관하게 해당 세력의 사기 붕괴 조건을 충족한다. 일부 전대의 retreating·surrendered만으로는 세력 전체 붕괴를 만들지 않는다.
- 유비군 패배는 손유 연합의 기본 패배이고, 손권군만 패배해도 유비군이 유지되면 전투를 계속한다.
- 조조군 기본 패배는 손유 연합 승리다.
- 같은 resolved turn에 연합과 조조군의 종료 조건이 동시에 성립하면 조조군 승리다.

판정에는 `original_cost`, `remaining_cost`, 전대 수와 항복 전대 수를 추가한다. 비용은 G8-00의 hull 근사치가 아니라 current/original composition과 setup ship type unit cost에서 다시 합산하므로 요구된 시작 코스트 기준을 그대로 사용한다.

## 상태와 흐름

`RedCliffsVictoryResolver.evaluate()`는 effect state를 변경하지 않고 `victory_result`를 만든다. 결과가 없으면 기존 `victory_check → continue_turn()` 경로가 유지된다. 결과가 있으면 같은 턴에 `battle_concluded`로 전환하며 다음 턴은 거부된다. resolution receipt와 battle snapshot에 결과를 보존한다.

기존 3D 증거창과 2D 지도는 명령권·viewer-safe projection을 그대로 유지한다. 이 단계는 새 이동·사격·표적 정보를 만들지 않는다.

## 검증

- `tests/test_demo_rc_g8_01_victory_conditions.gd`: `PASS 19 / FAIL 0`
- `tests/test_demo_rc_g8_00_combat_effects.gd`: `PASS 112 / FAIL 0`
- `tests/test_demo_rc_g8_00_combat_effects_ui.gd`: `PASS 35 / FAIL 0`
- `tests/test_s5_02_red_cliff_visible_fleet_3d_ui.gd`: `PASS 34 / FAIL 0`
- `tests/test_g10_qa01_red_cliffs_entry_e2e.gd`: `PASS 24 / FAIL 0`
- 전체 core `tests/run_tests.gd`: `701 / 0`

headless 환경은 기존 `user://logs` 쓰기 거부 경고와 시스템 인증서 읽기 경고를 출력하지만, 세 시험 모두 exit 0과 기능 실패 0이다.
