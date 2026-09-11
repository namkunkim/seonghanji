# DEMO-RC-G6-02 — 전술 임무 상시 변경과 판정 중 변경의 다음 턴 적용 UI

## 표시·조작 계약

전투 UI는 `viewer_fast_craft_missions(viewer_faction_id)`의 viewer-safe receipt만 사용한다. 자기 고속정 전대의 전투 중 불변 장비, 장비별 `supported_mission_ids`, authoritative 활성 임무, 이번 명령 초안, 다음 턴 예약과 최근 적용 이벤트를 표시한다. mutation에도 현재 viewer를 `requesting_faction_id`로 전달하므로 교차 세력 변경·취소는 원자 거부된다. 적 viewer의 임무·장비 상태는 표시하지 않는다.

현재 직접 명령 단계에서는 receipt의 `application=immediate`, `can_change`에 따라 지원 임무만 조작한다. 선택은 UI에 즉시 반영되지만 authoritative 활성 임무는 명령 제출 성공 시 원자 커밋된다. 제출 전에는 마지막 유효 선택으로 다시 바꿀 수 있고, 현재 활성 임무를 다시 고르면 초안이 취소된다.

판정 중에는 직접 편집할 전대가 없어도 자기 고속정 전대 패널을 유지한다. receipt의 `application=next_turn_queue`, `can_change`, `can_cancel`, `change_reason`을 그대로 소비해 다음 턴 예약·취소를 제공한다. 예약은 다음 턴 시작 때 한 번 승격되며, 20턴 판정 중에는 적용할 다음 턴이 없다는 사유와 함께 읽기 전용이다.

손권군은 해당 턴에 수동 제어를 선택한 경우에만 조작 가능하다. AI 위임 시 읽기 전용이며, 자기 AI 결정 receipt의 `fast_craft_mission_orders`와 동일 코어 validator 출처만 표시한다. 이벤트는 전역 단조 증가 `serial`의 append 순서를 소비하므로 예약 승격이 항상 최신 상태로 표시된다. UI에는 별도 임무 선택 계산이나 allowlist 복제본이 없다.

## 범위 경계

이번 기능은 전술 임무의 선택, 초안, 제출 적용, 다음 턴 예약·취소·승격 상태까지만 다룬다. 연료와 실제 G4 finite 자원의 자동 보급은 G6-03, 비상·조기 귀환은 G6-04 전투 UI가 각각 별도 viewer receipt로 표시한다. 임무 효과, 실제 표류·파괴, 구조 결과와 나포 결과는 G6-05 이후이며, 임무 UI가 결과를 계산하거나 성공·피해를 암시하지 않는다. 화면은 `Control` 기반 2D만 사용한다.

## 검증

- G6-02 core: `PASS 154 / FAIL 0`
- G6-02 UI headless: `PASS 53 / FAIL 0`
- G6-02 UI GPU: `PASS 55 / FAIL 0`
- G6-01 core/UI 회귀: `PASS 126 / FAIL 0`, `PASS 55 / FAIL 0`
- G4-01/G4-07 UI 회귀: `PASS 43 / FAIL 0`, `PASS 22 / FAIL 0`
- G5-01/G5-05 UI 회귀: `PASS 24 / FAIL 0`, `PASS 28 / FAIL 0`

집중 headless 및 관련 회귀 합계는 `PASS 505 / FAIL 0`이다.

GPU 캡처: `out/demo-rc-g6-02-fast-craft-mission/fast-craft-mission-1600x900.png` (1600×900, 103,997 bytes), SHA-256 `8851E16897F671635F26A82009D0D15F726523A1BD18B14AC6111C66AB910CEA`.

캡처는 판정 중 Liu 자기 전대의 불변 정찰 장비, 활성 연락 임무, 정찰 다음 턴 예약, 예약 취소 조작과 적용 턴을 보여 준다.
