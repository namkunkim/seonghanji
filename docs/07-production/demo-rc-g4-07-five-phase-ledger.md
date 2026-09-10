# DEMO-RC-G4-07 — 턴 전투 5단계 판정 원장

- Task ID: `DEMO-RC-G4-07`
- 공식/새 작업 제목: `DEMO-RC-G4-07 — 턴 전투 5단계 판정 원장`

## 범위

기존 외부 command phase는 유지하고, `resolve_turn` 내부 판정을 접적→포화→교전→강습→결착의 5단계 viewer 원장으로 표시한다. UI는 이벤트를 단계로 분류하거나 hidden event 수, 전투 결과, 승패를 계산하지 않는다. 코어가 공개한 단계명·상태·event·pending·digest만 렌더한다.

## Viewer API 권위

- 전체 자동 보기: `viewer_phase_ledger(viewer_faction_id, turn_number)`
- 요약과 타임라인: `viewer_phase_summary(viewer_faction_id, turn_number)`
- 단계별 보기: `viewer_phase(viewer_faction_id, phase_id, turn_number)`

원장 공개 전에는 `판정 완료 후 viewer 원장이 공개됩니다`만 표시한다. `no_visible_events`는 `가시 이벤트 없음`으로 표시하며 실제 empty인지 redaction으로 hidden인지 구분하거나 존재량을 추정하지 않는다. 각 실제 event는 공개된 `event_type`과 `ledger_event_id`만 목록화한다. 전체 64자리 `turn_digest`를 표시하며 UI refresh나 보기 전환으로 다시 계산하지 않는다.

## 5단계 표시 계약

1. 접적: 코어가 공개한 회복, 진형·무기 적용, 이동, 경로 교차, 탐지 event
2. 포화: `shot_authorized`와 자기 자원 event. 실제 발사·명중을 뜻하지 않는다.
3. 교전: 코어 `pending`
4. 강습: 코어 `pending`
5. 결착: `victory_check_required`와 pending. winner를 만들지 않는다.

위 매핑은 UI가 재분류하지 않고 viewer ledger 결과로만 표시한다.

## 1600×900 IA와 접근성

기존 좌측 단계/전대, 중앙 redacted 2D 지도, 우측 독립 ScrollContainer, 하단 고정 원장·CTA를 유지한다. 우측 원장은 다음 순서다.

- 제목과 전체 turn digest
- `자동 전체` 버튼과 키보드 접근 가능한 단계별 OptionButton
- 3열×2행 5단계 버튼. 단계명, 실제 event 수 또는 pending/no-visible을 색 외 문구로 표시
- 자동 보기의 다섯 단계 상세 또는 선택한 한 단계 상세

모든 전환 control은 최소 44px이며 원장 열람은 command draft를 변경하지 않는다.

## 검증 체크리스트

- [x] command phase에는 미확정 원장을 만들지 않는다.
- [x] 단계 수·순서·이름이 viewer summary와 정확히 일치한다.
- [x] 실제 event ID와 pending은 viewer phase API 결과만 표시한다.
- [x] `no_visible_events`는 hidden/empty를 구분하지 않는다.
- [x] 자동 전체와 단계별 조회가 같은 digest를 유지한다.
- [x] digest는 viewer 원문의 전체 문자열이며 UI에서 계산하지 않는다.
- [x] 적 resource reservation과 opaque identity가 viewer 원장/UI에 노출되지 않는다.
- [x] hit/damage/casualty/winner를 만들거나 표시하지 않는다.
- [x] 1600×900에서 5단계 버튼, digest, 스크롤, 하단 CTA가 겹치지 않는다.
- [x] 기존 이동·접촉·진형·무기·자원 UI 회귀가 녹색이다.
- [x] 제품 코드의 3D 참조가 0이다.

## 시험 결과

- G4-07 UI headless: `PASS 22 / FAIL 0`, exit 0
- G4-07 UI GPU: `PASS 24 / FAIL 0`, exit 0
- G4-07 core: `PASS 59 / FAIL 0`, exit 0
- G4-06 UI/core: `29/0`, `79/0`
- G4-05 UI/core: `30/0`, `80/0`
- G4-04 UI/core: `22/0`, `68/0`
- G4-03 UI/core: `21/0`, `111/0`
- G4-02 UI/core: `43/0`, `78/0`
- G4-01 UI/core: `43/0`, `236/0`
- G3 UI/core: `62/0`, `135/0`
- G2: `77/0`

## GPU 캡처

- 파일: `out/demo-rc-g4-07-five-phase-ledger/five-phase-ledger-1600x900.png`
- SHA256: `CAC6C74CC70A0EC362CF7ABA3DF83BBF5088386DD7D2F077D67B6BACD12641A9`
- 육안 확인: 다섯 단계가 3열×2행으로 모두 보이고 digest가 폭 안에서 줄바꿈된다. 이벤트 상세는 우측 독립 스크롤로 탐색하며 중앙 지도와 하단 `다음 턴` CTA는 고정되고 겹치지 않는다.

## 한계와 후속

- P1 잔여 없음.
- P2: 실제 OS 물리 입력·스크린리더·고 DPI는 자동 Control/GPU 시험 범위 밖이다.
- P2: 이벤트가 매우 많은 턴의 검색·접기·가상화는 후속 로그 탐색 개선 대상이다.
