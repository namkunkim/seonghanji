# DEMO-RC-G6-04 — 비상 귀환 기준·목적지 재탐색·조기 귀환·UI 경고 UI

## 표시·조작 계약

전투 UI는 `viewer_fast_craft_returns(viewer_faction_id)`의 자기 세력 receipt만 사용한다. 자기 고속정마다 잔여 연료, 가장 가까운 도달 가능 보급원, boundary 기준 필요 연료, 한 턴 예비 연료, 강제귀환 threshold, 거리, 예상 턴과 코어가 선택한 귀환 경로를 표시한다. 2D 지도는 현재 `live_navigation` 위치에서 receipt의 zone-boundary 목적지까지 점선 경로와 목적지 ring을 그린다. 지도 라벨은 짧은 보급원 표기와 공통 충돌 회피 오프셋을 사용해 밀집 영역에서도 전대·보급원·귀환 ETA가 겹치지 않게 배치한다. 거리·연료·ETA·목적지 선정은 UI가 다시 계산하지 않는다.

threshold 전에는 receipt의 `can_request_early`와 `can_cancel`에 따라 조기 귀환과 취소를 제공한다. 두 mutation 모두 현재 viewer를 `requesting_faction_id`로 전달하므로 타 세력 전대 조작은 상태 변경 없이 거부된다. threshold 이하 `forced_return`은 양쪽 조작을 잠그고 취소 불가 경고를 표시한다. 도달 가능한 보급원이 없는 `stranded_risk`는 필요 연료·거리·ETA를 임의 산출하지 않고 위험 경고만 표시한다.

귀환 계획과 목적지는 매 판정 턴 코어가 재평가한다. 패널은 단조 증가 `serial` 순서의 `fast_craft_return` 계획·재탐색·취소 이벤트와 `fast_craft_fuel_consumed`의 실제 이동 거리, 연료 before/used/after receipt를 표시한다. 귀환 중인 전대의 명령 override와 hold-fire, 보급 완료 뒤 intent 해제는 코어 권위이며 UI에 복제 규칙이 없다.

## 정보 경계와 후속 범위

적 viewer는 상대 고속정의 연료, threshold, 도달 가능한 보급원, ETA, 경로, 상태와 조작을 받지 않는다. 유비 viewer에는 유비·손권 상호 보급 계약에 따른 도달 가능 source만 코어가 선택해 공개하며 조조 source는 노출하지 않는다.

이번 범위는 비상·조기 귀환 판단, 경로·재탐색, 실제 이동 연료 소비와 경고까지만 다룬다. 연료 0 이후 표류·구조·나포와 보급함 무력화는 G6-05의 별도 viewer receipt·읽기 전용 카드가 담당한다. 실제 damage/boarding trigger는 G8-00 경계다. 화면은 `Control` 기반 2D 전용이며 3D 자산이나 경로는 사용하지 않는다.

## 검증

- G6-04 core: `PASS 46 / FAIL 0`
- G6-04 UI headless: `PASS 42 / FAIL 0`
- G6-04 UI GPU: `PASS 44 / FAIL 0`
- G6-02 core/UI 회귀: `PASS 154 / FAIL 0`, `PASS 53 / FAIL 0`
- G6-03 core/UI 회귀: `PASS 53 / FAIL 0`, `PASS 39 / FAIL 0`
- G4-02 core/UI 회귀: `PASS 78 / FAIL 0`, `PASS 43 / FAIL 0`
- G4-06 core/UI 회귀: `PASS 79 / FAIL 0`, `PASS 29 / FAIL 0`
- G5-03 core/UI 회귀: `PASS 40 / FAIL 0`, `PASS 20 / FAIL 0`
- G5-05 core/UI 회귀: `PASS 57 / FAIL 0`, `PASS 28 / FAIL 0`

직접 실행한 headless 집중·회귀 합계는 `PASS 761 / FAIL 0`이다.

GPU 캡처: `out/demo-rc-g6-04-fast-craft-return/fast-craft-return-1600x900.png` (1600×900, 139,387 bytes), SHA-256 `71ADAAC8192D3D3A59B609DD79078911B4C41E35B3BFE3AF71BD419F98D61274`.

캡처는 유비 viewer의 보급 영역과 고속정 귀환 목적지, 지도 경로, 잔여·필요·예비·threshold, 거리·ETA, 조기 귀환/취소 조작, 실제 이동 거리 기반 연료 소비 이벤트를 보여 준다. 적 정보와 G6-05 결과는 없다.
