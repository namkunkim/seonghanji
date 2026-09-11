# DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위 UI

## 표시 계약

2D 전술 지도는 `viewer_fast_craft_supply(viewer_faction_id)`의 `sources`만 그린다. 보급함, 강습모함, 아군 거점의 위치·반경·턴당 처리량을 구분하며, 유비·손권 상호 보급 영역은 아군 정보로 함께 표시한다. 조조 영역은 유비·손권 viewer에 노출하지 않고 조조 viewer에는 조조 자체 영역만 제공한다.

자기 고속정 패널은 같은 viewer receipt의 연료, 자동 대기열, 진입 턴, 연속 정박 진행, source-local 처리 순위, 처리량과 append-order 이벤트를 표시한다. 대기열은 영역 진입 시 자동 생성되고 실제 이동 거리 또는 보급원 이동·영역 이탈 시 중단된다. 수동 보급 버튼이나 mutation 경로는 없다.

결정론적 처리 우선순위는 코어가 공개한 `remaining_fuel_ascending → entry_turn_ascending → squadron_id_ascending`과 각 queue row의 `priority_rank`를 그대로 표시한다. UI는 거리, 정박 완료, 정렬, 처리량을 계산하지 않는다.

## 실제 G4 유한 자원 연동

추상 `ammo_basis_points`는 UI와 viewer receipt에서 사용하지 않는다. 현재 탄약·특수 자원은 `viewer_snapshot().own_combat_resources`의 실제 G4 weapon row만 표시하며, 완료 이벤트는 viewer-safe `combat_resource_before`, `combat_resource_after`, `combat_resource_refill`을 소비한다. 집중 테스트는 뇌격 고속정의 실제 특수 자원 1→12 refill receipt를 `뇌격 특수 +11`로 표시하고 임의 탄약 증가를 만들지 않음을 검증한다.

연료는 supply receipt의 0~10000 bp 자원이며 최대치를 넘지 않는다. 보급은 이동과 사격 자원 소모 뒤 턴 말에 실행된다. 에너지·열·함재기 회복 규칙을 대신하거나 조작하지 않는다.

## 범위 경계

이번 UI는 자동 보급 영역, queue, 한 턴 정박, 중단, 처리 순위·처리량, 연료와 실제 G4 finite refill 완료만 다룬다. 임무 효과, 자동 귀환, 표류, 구조, 나포, 보급원 재고·손상과 기지 재장전은 G6-04~06 범위이며 선점하지 않는다. 화면은 `Control` 기반 2D 전용이다.

## 검증

- G6-03 core: `PASS 53 / FAIL 0`
- G6-03 UI headless: `PASS 39 / FAIL 0`
- G6-03 UI GPU: `PASS 41 / FAIL 0`
- G6-02 core/UI 회귀: `PASS 154 / FAIL 0`, `PASS 53 / FAIL 0`
- G6-01 core/UI 회귀: `PASS 126 / FAIL 0`, `PASS 55 / FAIL 0`
- G4-02 이동 UI: `PASS 43 / FAIL 0`
- G4-06 core/UI: `PASS 79 / FAIL 0`, `PASS 29 / FAIL 0`
- G5-03/G5-05 UI: `PASS 20 / FAIL 0`, `PASS 28 / FAIL 0`

직접 실행한 headless 집중·회귀 합계는 `PASS 679 / FAIL 0`이다.

GPU 캡처: `out/demo-rc-g6-03-fast-craft-supply/fast-craft-supply-1600x900.png` (1600×900, 127,214 bytes), SHA-256 `E2A023DC60C289C8ACA17E238FCB74F178583B0485784EB5F16B63C7BFE0B0B7`.

캡처는 유비 viewer의 유비·손권 보급함/강습모함/거점 영역, 고속정 연료 6000/10000 bp, 자동 queue, T1 진입, 정박 0/1턴, 순위 1과 거점 처리량 4를 보여 준다. 추상 탄약 게이지와 적 보급 정보는 없다.
