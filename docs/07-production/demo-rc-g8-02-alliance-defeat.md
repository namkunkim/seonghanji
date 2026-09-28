# DEMO-RC-G8-02 — 유비군 패배와 손유 연합 판정의 관계

## 경계

G8-01은 `normal-demo-victory-v1`의 세력별 70%bp 비용 손실·전 전대 항복만 세력 단위로 판정했고, 연합 승패는 `defeated.liu_bei` 하나만 소비했다. `data/red-cliffs-victory-rules.json`의 `alliance.member_faction_ids: ["liu_bei","sun_quan"]`는 이미 존재했지만 `evaluate()`가 읽지 않는 죽은 필드였다. 이 Task는 `demo-rc-05-result-campaign-return.md`의 "그 밖의 전력 붕괴는 손유 연합과 조조군 각각의 시작 코스트 대비 70% 이상 손실로 판정한다"를 배선해 이 필드를 실제로 소비하게 한다.

기함 파괴·탈출점·20턴 잔존비 비교는 이번에도 G8-03 경계다. `data/red-cliffs-victory-rules.json`의 `statement`가 이미 "이동·탈출·기함 특수 결과와 20턴 비교는 후속 G8-03에 남긴다"를 명시하고 있고, G8-01 문서도 "기함 격침·탈출점·20턴 잔존비 비교는... G8-03에 남긴다"를 기함 소유 세력을 구분하지 않고 적었다 — 유비 기함도 조조 기함과 함께 G8-03에서 다룬다. 장수 casualty도 계속 pending이다.

## 규칙과 우선순위

`docs/07-production/demo-rc-05-result-campaign-return.md`의 승패 문단을 세 조건으로 분해한다.

1. **유비군 개별 조건** (기존 G8-01, 변경 없음): 유비군 자신의 시작 코스트 70%bp 이상 손실 또는 유비군 전 전대 항복 → 연합군 패배.
2. **연합 결합 조건** (신규): 유비군 + 손권군의 **결합** 시작 코스트 대비 **결합** 잔존 코스트 손실이 70%bp 이상이면, 유비군 개별 조건을 아직 충족하지 않았어도 연합군 패배다. 손권군이 단독으로 크게 손실을 입어도 유비군이 거의 무사하면 결합 손실이 70%에 못 미쳐 연합은 유지된다 — 이것이 "손권군 단독 패배는 유비군이 계속 싸울 수 있으면 즉시 종료하지 않는다"가 실제로 의미하는 바다.
3. **손권군 개별 조건은 연합 판정에 직접 쓰이지 않는다.** 손권군 자신의 70%bp 손실이나 전 전대 항복(`defeated.sun_quan`)은 evidence로만 남고, 결합 손실 계산에 자동 반영될 뿐 단독으로 연합을 끝내지 않는다. 손권군의 사기 붕괴(전 전대 항복)는 비용을 줄이지 않으므로(항복한 전대의 함선은 파괴되지 않는 한 `current_composition` 비용을 그대로 유지한다) 결합 손실 계산에도 기여하지 않는다 — 손권군만 완전히 항복해도 유비군이 무사하면 연합은 계속된다.

결합 손실 bp 계산은 세력별 계산과 같은 공식을 재사용한다: `floor((Σoriginal_cost - Σremaining_cost) × 10000 / Σoriginal_cost)`, `Σ`는 `_rules.alliance.member_faction_ids`를 순회한다. 결합 전용 threshold는 두지 않고 기존 `loss_threshold_basis_points`(7000)를 그대로 쓴다 — 원문이 결합과 개별에 다른 수치를 요구한다는 근거가 없고, 별도 필드를 추가하면 `data/red-cliffs-victory-rules.json`의 계약 검증(`evaluate()`가 정확히 이 값들만 허용)을 손대야 할 이유가 늘 뿐이다.

조조군 판정은 변경하지 않는다. 조조군은 이 전투에서 동맹이 없으므로 "조조군 각각의"는 이미 구현된 개별 70%bp 조건과 같다.

같은 resolved turn에 연합과 조조군이 동시에 종료 조건을 충족하면 기존 `simultaneous_winner_faction_id`(조조군) 우선이 그대로 적용된다. 연합 패배가 유비군 개별 조건에서 왔는지 결합 조건에서 왔는지는 `reason_codes`에 `liu_bei_terminal_condition` 또는 `alliance_combined_loss_threshold`로 구분해 남기고, 동시 종료는 기존과 같이 `simultaneous_terminal_conditions_cao_priority` 하나로 남긴다(어느 쪽이 연합을 무너뜨렸는지는 조조군 승리라는 결과를 바꾸지 않으므로 세분화하지 않는다).

## 상태와 흐름

`evaluate()`의 반환값에 `alliance_evidence: {member_faction_ids, original_cost, remaining_cost, loss_basis_points, loss_threshold_reached}`를 추가한다. 기존 `faction_evidence`(세력별 3행)는 그대로 유지하므로 G8-01의 소비자와 시험은 변경 없이 통과한다. `RedCliffsVictoryResolver`는 여전히 순수 함수이며 effect state를 바꾸지 않는다. `red_cliffs_turn_battle.gd`의 결과 소비(`winner_present` → `battle_concluded` 전환)는 변경하지 않는다 — 이미 `victory_result.winner_present`만으로 배선돼 있어 새 evidence 필드를 몰라도 정상 동작한다.

## 검증

- `tests/test_demo_rc_g8_02_alliance_defeat.gd`: `PASS 14 / FAIL 0`
- `tests/test_demo_rc_g8_01_victory_conditions.gd`: `PASS 19 / FAIL 0` (회귀 없음 — sun-only 시험은 결합 손실도 70% 미만인 입력이라 그대로 통과한다)
- `tests/test_demo_rc_g8_00_combat_effects.gd`: `PASS 112 / FAIL 0`
- 전체 core `tests/run_tests.gd`: `701 / 0`

headless 환경의 기존 `user://logs` 쓰기 거부 경고는 이번에도 기능 실패가 아니다.
