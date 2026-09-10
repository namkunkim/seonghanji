# DEMO-RC-G4-03 — 경로 교차 요격·탐지 기반 기회 사격

- Task ID: `DEMO-RC-G4-03`
- 공식/새 작업 제목: `DEMO-RC-G4-03 — 경로 교차 요격·탐지 기반 기회 사격`

## UI 경계

G4-02의 순수 2D 전술 지도 위에 코어가 확정한 탐지 상태와 판정 이벤트만 표시한다. UI는 탐지, 경로 교차, 거리, 방위, 사격각 또는 사격 가능 여부를 계산하지 않는다. 3D 모델·GLB·3D 시네마틱은 사용하지 않는다.

화면이 소비하는 공개 API는 `viewer_snapshot(viewer_faction_id)`과 `viewer_turn_log(viewer_faction_id)`이다. 전자는 own squadrons/navigation과 `visible_contacts`, `visible_tactical_events`의 redacted 결과만 제공하고, 후자는 viewer별 원장만 제공한다. raw `snapshot`, `live_navigation`, `turn_log`, resolve receipt의 적 중첩 자료는 지도·라벨·로그에 전달하지 않는다.

표시 계약은 다음과 같다.

- 새 `undetected`: 코어가 contact 자체를 omit하며 적 마커·이름·tooltip·선택 hit-test·로그를 모두 표시하지 않는다.
- `estimated`: 실제 live 위치나 target ID 대신 opaque `contact_id`와 코어가 제공한 `last_known_position`에 점선 원, `추정 접촉`, 마지막 확인 턴, `실제 위치와 다를 수 있음`을 표시한다.
- stale/lost: target ID 없이 last-known 좌표·마지막 확인 턴·`stale`과 위치 불확실성만 표시한다.
- `confirmed`: 코어가 공개한 위치에 실선 마커와 `확인 접촉` 문구를 표시한다.
- 요격/기회 사격: 코어 receipt의 shooter/target/event 순서와, 아군 사수에게 허용된 range/distance/bearing/facing/arc를 읽어 지도 선과 이벤트 목록으로 표시한다. 피격 측에는 적 사수의 정확한 기하 정보를 공개하지 않는다. 사격 결과는 `shot_authorized`, 피해는 `damage_pending`으로만 표시하며 피해량·격침·승자를 만들지 않는다.

탄약·자원 소모는 G4-06, 피해·사상·승패 판정은 각각의 후속 전투/결과 Task 범위라 이 단계에서 만들거나 표시하지 않는다.

## 1600×900 정보 구조

좌측 단계/전대 목록, 중앙 전술 지도, 우측 이동 초안이라는 G4-02의 구조를 유지한다. 판정 이후 우측에는 `접촉 및 기회 사격` 섹션을 노출하고, 탐지 상태는 색만이 아니라 `추정`·`확인` 문구와 서로 다른 점선/실선 도형으로 구분한다. 하단 턴 원장은 탐지·교차·사격 건수와 `피해 판정 후속`을 기록한다. 이벤트가 많으면 우측 독립 스크롤과 지도 이벤트 순번을 함께 사용한다.

## 검증 체크리스트

- [x] 미탐지 적은 지도, 라벨, 선택 hit-test에서 모두 제외된다.
- [x] 추정/stale 접촉은 실제 live 위치·ID·편성·명령·경로를 누설하지 않고 last-known 좌표/턴/불확실성만 표시한다.
- [x] 확인 접촉은 코어가 허용한 위치와 명확한 문구만 표시하며 예상 명령을 확정 정보처럼 표현하지 않는다.
- [x] 지도와 로그는 viewer별 redacted API만 소비한다.
- [x] 경로 교차, 사거리, 사격각과 event 순서를 UI가 재계산하지 않는다.
- [x] `damage_pending=true`에서 피해·격침·승자 UI가 없다.
- [x] HOLD/MOVE, 손권 manual/AI/dont-ask, 20턴 pending, zoom/pan/waypoint 동작이 유지된다.
- [x] 1600×900에서 지도, 접촉/사격 목록과 고정 CTA가 읽히며 44px 입력 크기를 유지한다.
- [x] 신규 경로의 Node3D/GLB/3D 참조가 0이다.

## 시험 및 캡처

- G4-03 UI headless: `PASS 21 / FAIL 0`, exit 0
- G4-03 UI GPU: `PASS 23 / FAIL 0`, exit 0
- G4-03 core: `PASS 111 / FAIL 0`, exit 0
- G4-02 UI/core: `PASS 43 / FAIL 0`, `PASS 78 / FAIL 0`, exit 0
- G4-01 UI/core: `PASS 43 / FAIL 0`, `PASS 236 / FAIL 0`, exit 0
- G3 UI/core 및 G2: `PASS 62 / FAIL 0`, `PASS 135 / FAIL 0`, `PASS 77 / FAIL 0`, exit 0

GPU 캡처는 `out/demo-rc-g4-03-interception-detection/interception-detection-1600x900.png`, 1600×900, SHA256 `4DEF3501155184402C6F1A689A1517C6D708F8D00ED88AF22CA8D077A2C7AB1A`이다. Intel Arc Vulkan에서 own 전대만 표시되는 지도, opaque 추정 접촉, 독립 스크롤과 고정 CTA를 육안 확인했다. 이 캡처의 접촉은 추정 상태이므로 기회 사격을 승인하지 않는다. 실제 OS 물리 마우스의 장치별 감도는 자동 Control/GPU 시험 범위 밖이다.
