# DEMO-RC-G8-03 — 조조 기함 파괴·탈출, 연합 탈출과 20턴 판정

## 경계

G8-01·G8-02가 미룬 마지막 세 기본 종료 조건을 닫는다: 기함 파괴, 지정 탈출 지점 도달, 20턴 시점 잔존 코스트 비율 비교. `data/red-cliffs-victory-rules.json`의 `result_contract.future_conditions`가 정확히 이 셋(`["flagship","escape","turn_limit"]`)을 미결로 표시해 왔고, G8-01 문서도 "기함 격침·탈출점·20턴 잔존비 비교는... G8-03에 남긴다"를 기함 소유 세력을 구분하지 않고 적었다 — **유비 기함도 조조 기함과 함께 이번에 닫는다.** 이 Task 이후 `future_conditions`는 빈 배열이다. 장수 casualty(`result_contract.commander_casualties`)는 여전히 G8-04 경계다.

## 규칙과 근거

`docs/07-production/demo-rc-requirements-interview.md` §10과 `demo-rc-05-result-campaign-return.md`의 승패 문단을 다음 세 그룹으로 배선했다.

### 1. 기함 파괴

- 유비 기함(전대 `RC-LIU-SQ-02`, 제갈량) 격침은 **즉시** 연합군 패배다 — 유비군 자신의 70%bp 손실·항복 조건과 별개의 독립 조건이다.
- 조조 기함(전대 `RC-CAO-SQ-01`, 조조) 격침은 **남은 조조군과 관계없이** 연합군 승리다.
- "격침"은 G8-00이 이미 계산하는 전대 `damage_state == "destroyed"`(hull 0)를 그대로 쓴다. 별도 기함 HP나 판정을 새로 만들지 않는다 — 기함도 결국 그 전대의 하나이고, G8-00은 이미 전대 단위로만 hull을 추적한다.
- `RedCliffsCombatEffects.victory_inputs()`가 `_setup.squadrons`에서 `flagship:true`인 유비·손권·조조 중 유비·조조 두 세력만(손권 기함은 승패에 관여하지 않는다) 조회해 `flagships.<faction_id>.destroyed`를 판정 입력에 포함한다. state에 없는 기함 전대(있을 수 없지만)는 보수적으로 파괴로 취급한다.

### 2. 탈출 지점

- "퇴각은 지정 탈출 지점까지 실제 이동한 뒤 턴 종료 판정에서 성공한다"(요구사항 인터뷰 §5)를 문자 그대로 구현한다 — 별도 퇴각 명령 타입을 만들지 않고, 매 턴 종료 시 위치만 확인한다. 일반 MOVE/HOLD 명령으로 그 위치에 도달하면 그것으로 충분하다.
- 좌표는 이번 Task에서 새로 정의했다(원전 미기재, `battlefield_bounds: [0,0,1600,900]` 안에서 결정). 유비·손권 시작 위치가 x 220~410·y 500~720(서남쪽)이고 조조 시작 위치가 [1110,330](동북쪽)이므로, 각 진영의 "본대 방향" 가장자리를 탈출 지점으로 삼았다: 조조군 탈출 지점 `[1600,300]`(동쪽 경계, 조조 시작 y와 근접), 연합군 탈출 지점 `[0,650]`(서쪽 경계, 유비/손권 시작 y 대역과 근접). 도달 반경은 G6-05 구조 판정의 `contact_radius: 40` 선례보다 약간 넉넉한 `60`으로 잡았다 — 탈출은 구조보다 판정 실패 시 리스크가 크므로(대규모 퇴각 함대가 좌표 오차로 실패하면 안 됨) 더 관대한 반경을 뒀다.
- 조조 기함이 조조군 탈출 지점에 도달하면 연합군 승리(남은 조조군과 무관하다는 점에서 기함 격침과 대칭).
- 유비 기함 + **필수 전대**가 연합군 탈출 지점에 도달하면 **제한적** 연합군 승리다. "필수 전대"는 원전에 정의가 없어, 기존 데이터 모델에 이미 있는 개념을 재사용했다: 유비 기함이 속한 함대(`RC-LIU-FLT-01`)의 `squadron_ids` 전체(`RC-LIU-SQ-01`, `RC-LIU-SQ-02`) — 새 개념을 만들지 않고 "기함과 같은 함대로 묶인 전대들"로 해석했다. 독립 배치된 고속정대(`RC-LIU-FC-01`)는 이 함대에 속하지 않으므로 필수 전대가 아니다.
- 도달 판정은 해당 전대가 `capabilities.operational == true`(파괴·항복하지 않음)이고 실제 turn-resolved 위치가 탈출 지점 반경 안에 있어야 한다. 파괴된 전대가 우연히 그 좌표에 남아 있어도 도달로 세지 않는다.
- 위치·함대 소속 정보는 `RedCliffsVictoryResolver`가 갖지 않는다(순수 비용/사기 판정기로 유지). `red_cliffs_turn_battle.gd`가 `_escape_status()`로 이번 턴 `movement_result.live_navigation` + `applied_setup.fleet_groups` + `effect_result.state.squadrons`를 조합해 `{"cao_cao": bool, "liu_sun_alliance": bool}`만 계산해 넘긴다.

### 3. 20턴 잔존 코스트 비율

- "20턴까지 다른 종료 조건이 없으면 시작 코스트 대비 잔존 코스트 비율이 높은 측이 승리하며 동률은 조조군 승리다"를 그대로 구현했다. 손유 연합 비율은 G8-02가 이미 계산하는 결합 `original_cost`/`remaining_cost`를 재사용한다.
- 비율 비교는 부동소수점 나눗셈 대신 교차곱(`alliance_remaining × cao_original` vs `cao_remaining × alliance_original`)으로 한다 — 이 프로젝트의 "결정론적 정수 수학" 원칙을 따른다.
- `turn_limit: 20`을 `red-cliffs-victory-rules.json`에 추가하고 `RedCliffsVictoryResolver`가 매 턴 `victory_inputs.turn >= _rules.turn_limit`일 때만 이 분기를 검사한다. 다른 조건이 이미 같은 턴에 성립했으면 이 분기는 아예 평가되지 않는다(다른 조건이 우선).

## 상태와 흐름 변경

- `red_cliffs_turn_battle.gd`의 `_state.phase = "battle_concluded" if winner_present else ("turn_limit_reached" if turn()>=MAX_TURNS else "victory_check")` 삼항식은 **손대지 않았다.** 20턴 비교가 이제 항상 승자를 만들어내므로(동률도 조조 승리로 귀결) `turn_limit_reached` 분기는 사실상 도달 불가능한 방어적 코드로 남는다 — `continue_turn()`의 `"turn_limit_reached"` 거부 분기와 UI의 `PHASE_LABELS`/`_status_for_phase`의 해당 분기도 마찬가지로 남겨 뒀다. 삭제하지 않은 이유: 이 문자열을 직접 주입하는 기존 fixture 시험(`test_demo_rc_g6_06_supply_inventory.gd`)이 있고, 무해한 방어 코드를 지우는 것보다 남겨 두는 편이 회귀 위험이 적다.
- `receipt.victory_inputs`에 저장하는 값을 `effect_result.victory_inputs`(기함 정보만 포함)에서 `enriched_victory_inputs`(기함 + 탈출 정보 모두 포함, 실제로 resolver에 넘긴 것과 동일한 값)로 바꿨다 — receipt에 남는 입력과 실제 판정 입력이 항상 일치해야 하기 때문이다.
- `evaluate()` 반환값에 `victory_type: "decisive" | "limited"`을 추가했다. 유일하게 `"limited"`가 되는 경우는 다른 결정적 조건(기함·비용·항복·탈출을 포함한 조조군 패배) 없이 오직 연합군 탈출만으로 이긴 턴이다. G8-04 결과 화면이 "완전 승리"와 "제한적 승리"를 구분해야 하므로 여기서 미리 신호를 만들어 둔다.

## 회귀: 20턴 상한의 의미 변화

기존 여러 시험이 손실 없는(또는 미미한 손실의) 20턴 HOLD 루프 끝에 `phase() == "turn_limit_reached"`(승자 미정, 다음 판정 대기)를 기대하고 있었다. 20턴 비교가 이제 **항상** 승자를 내므로 이 기대값은 전부 틀렸다 — G8-00/G8-01 문서가 이미 "G8-00/G8-01 이전의 현재 천장"이라고 명시해 둔, G8-03이 오면 바뀔 것으로 예정된 자리다. 다음 시험의 종료 phase/문구 기대값을 `battle_concluded`/`승패 확정`으로 갱신했다(승자 값 자체는 각 fixture의 실제 AI 행동에 따라 달라 개별 확인함, 무조건 조조 동률이 아니다 — 예를 들어 `test_demo_rc_g4_01_turn_battle.gd`는 유비 HOLD·조조 AI가 소폭 피해를 입어 연합군이 `turn_limit_alliance_cost_ratio_higher`로 승리한다):

- `tests/test_demo_rc_g4_01_turn_battle.gd`
- `tests/test_demo_rc_g4_01_turn_battle_view.gd`
- `tests/test_demo_rc_g5_04_sun_control_contract.gd`
- `tests/test_demo_rc_g6_05_fast_craft_recovery.gd`
- `tests/test_demo_rc_qa01_e2e.gd`
- `tests/test_demo_rc_qa03_full_scenario_loop.gd`

또한 `tests/test_demo_rc_g8_01_victory_conditions.gd`·`tests/test_demo_rc_g8_02_alliance_defeat.gd`의 `_inputs()` 헬퍼에 `flagships`/`escapes` 기본값(모두 비발동)을 추가했다 — `evaluate()`가 이제 이 두 키를 필수로 요구하기 때문이다. G8-01의 `future_conditions_pending == ["flagship","escape","turn_limit"]` 기대값도 `== []`로 갱신했다.

`tests/test_demo_rc_g4_01_turn_battle_view.gd`에서 이번 작업과 무관하게 이미 깨져 있던 한 줄(`TurnStatus` 텍스트가 실제로 만든 적 없는 "후속 구현 대기" 문구를 기대)을 발견해 같은 김에 고쳤다 — 실제 현재 `victory_check` 단계 문구로 교체했다. G8-03 범위는 아니지만 같은 파일을 손대는 김에 정리했다.

## 발견한 무관한 사전 결함 (수정하지 않음)

전체 회귀(관련 시험 70개 개별 실행)에서 이번 작업과 무관한 기존 실패를 발견했다. 전부 이 Task가 건드린 파일 밖이거나 HEAD에 이미 존재하던 문제라 손대지 않았다.

| 파일 | 증상 | 근거 |
|---|---|---|
| `tests/test_demo_rc_01_playable_entry.gd` | 결정론 실패 1건 | 세션 시작 시점에 이미 다른 세션이 수정 중이던 파일(레거시 `Campaign.scenario_03` 경로, 현재 정본 경로와 무관) |
| `tests/test_scn03_red_cliff_manifest_activation.gd` | 12 실패 | 위와 동일하게 세션 시작 시점 이미 dirty |
| `tests/test_demo_rc_lt03_deployment_core.gd` | 4 실패 | git 미추적 파일(다른 세션의 작업물로 추정) |
| `tests/test_demo_rc_g4_03_interception_detection_ui.gd` | 3 실패 | `RC-LIU-FC-01` 고속정 전대가 G6-01 이후 기본 편성에 추가됐는데 이 구형 G4-03 fixture가 갱신되지 않은 staleness. HEAD에서도 동일하게 실패 |
| `tests/test_demo_rc_g5_01_fog_estimated_fire_ui.gd` | 1 실패 | `red-cliffs-phase-ledger-rules.json`의 정적 `pending` 목록이 G8-00 이후에도 갱신되지 않은 staleness. HEAD에서도 동일하게 실패 |
| `tests/test_demo_rc_lt02_campaign_loop.gd` | 파싱 오류 | 스크립트 자체 문법 오류, 이 세션에서 만들지 않음 |
| `tests/test_demo_rc_qa02_native_input.gd` | 결과 없음 | GPU 전용 native-input 시험, headless 환경 한계(기존 관례) |

## 검증

- `tests/test_demo_rc_g8_03_flagship_escape_turnlimit.gd`: `PASS 32 / FAIL 0`
- `tests/test_demo_rc_g8_01_victory_conditions.gd`: `PASS 19 / FAIL 0`
- `tests/test_demo_rc_g8_02_alliance_defeat.gd`: `PASS 15 / FAIL 0`
- `tests/test_demo_rc_g8_00_combat_effects.gd`: `PASS 112 / FAIL 0`
- `tests/test_demo_rc_g4_01_turn_battle.gd`: `PASS 237 / FAIL 0`
- `tests/test_demo_rc_g4_01_turn_battle_view.gd`: `PASS 43 / FAIL 0`
- `tests/test_demo_rc_g5_04_sun_control_contract.gd`: `PASS 180 / FAIL 0`
- `tests/test_demo_rc_g6_05_fast_craft_recovery.gd`: `PASS 93 / FAIL 0`
- `tests/test_demo_rc_qa01_e2e.gd`: `77 passed / 0 failed`
- `tests/test_demo_rc_qa03_full_scenario_loop.gd`: `통과 274 · 실패 0`
- 전체 core `tests/run_tests.gd`: `35섹션 · 701/0`
- 위 목록 외 관련 시험(G2~G7, G8, S5-02, A-05, QA, SCN-03 계열) 70개 개별 headless 실행: 본 표의 무관 사전 결함 7건을 제외하고 전부 통과.

headless 환경의 기존 `user://logs` 쓰기 거부 경고는 이번에도 기능 실패가 아니다.

## 검토 포인트

| # | 쟁점 | 상태 |
|---|---|---|
| 1 | 탈출 지점 좌표 `[1600,300]`/`[0,650]`와 반경 `60`은 원전 근거 없이 이번 Task에서 결정했다 | 미해소 — 밸런스 테스트 대상. 명백히 부적절하면 조정 |
| 2 | "필수 전대"를 유비 기함의 함대 전체로 해석했다(고속정대 등 독립 배치 전대 제외) | 미해소 — 사용자가 다른 정의(예: 코스트 상위 N개 전대)를 원하면 재설계 |
| 3 | 유비 기함 파괴를 G8-03에서(원 체크리스트 문구는 "조조 기함"만 명시) 함께 닫은 것 | 해소 — G8-00·G8-01 문서가 세력 구분 없이 "기함 격침"을 G8-03에 넘겼으므로 범위 안이라고 판단 |
