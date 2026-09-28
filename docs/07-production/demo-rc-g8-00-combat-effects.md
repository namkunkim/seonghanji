# DEMO-RC-G8-00 — 전투 피해·사기·센서·지형 효과 적용

## 경계

G4의 `shot_authorized`/`estimated_fire_authorized`와 G5-06의 네 `effect_intents`를 실제 전투 상태에 적용한다. 같은 턴의 모든 일반 사격과 연쇄 폭발은 피해 전 snapshot에서 산출하고 `event_id` 오름차순으로 target별 합산한다. 적용 뒤 SHP-05 상태를 G6-06 재고 reducer에 동기화한 다음 보급을 판정한다. 최종 receipt는 `victory_inputs`만 만들며 winner와 장수 부상·전사·포로 판정은 만들지 않는다.

판정 순서는 `resource-authorized fire → chain recheck/trigger → atomic combat effects → SHP-05 status sync → outbound supply → phase ledger → victory_inputs`다. 입력 batch의 malformed row, 중복/replay event ID, wrong turn은 전체를 digest 불변으로 거부한다.

## 확정 수치

- 최대 hull은 `Σ(original ship count × ship_type.unit_cost × 10)`이다. 임무 장비 비용은 중복 합산하지 않는다.
- 기본 명중 bp는 intercept 8000, line fire 7000, artillery 6500, torpedo 6000이다. `clamp(base + (shooter fire% - target defense%) × 100, 1000, 9500)`에 command accuracy bp를 half-up 곱한다. 무기 allocation은 선택 단계에서 이미 소비했으므로 다시 곱하지 않는다.
- roll은 `sha256(profile_id|turn|event_id)` 첫 8 hex를 10000으로 나눈 나머지이며 `roll < chance`가 명중이다. estimated fire는 여기에 confidence bp를 half-up 곱하고, 봉인된 contact→actual target과 aim-to-actual 거리 gate를 함께 요구한다. 반경은 intercept 35, line fire 25, artillery 55, torpedo 45다.
- 명중 피해는 intercept 70, line fire 100, artillery 140, torpedo 180이다. hull band는 operational 7500bp 이상, moderate 4000–7499, heavy 1–3999, destroyed 0이다.
- 누적 함선 손실은 `floor(original ship total × cumulative hull loss / maximum hull)`이며 overkill은 현재 hull에서 차단한다. 손실은 immutable original composition의 `ship_type_id` 오름차순으로 배분한다. 장수 casualty는 pending이다.
- G6-06 보급함 상태는 전대 단위다. 전대 hull band를 생존한 모든 SHP-05에 동일하게 적용하고, 위 composition casualty 배분으로 제거된 SHP-05만 destroyed count로 넘긴다. 개별 보급함 hull이나 임의의 per-ship damage 분배는 만들지 않는다.
- morale은 10000bp에서 시작한다. 일반 명중은 최소 300bp와 `ceil(damage × 10000 / (maximum hull × 5))` 중 큰 값을 잃고, 실제 함선 손실마다 200bp, 연쇄 폭발로 3500bp를 잃는다. steady 6000 이상, shaken 3000–5999, retreating 1–2999, surrendered 0이다. shaken은 이번 턴 승인 행동을 취소하지 않는다. retreating은 다음 명령부터 공격·임무 변경 불가/강제 퇴각이며 실제 탈출점 이동은 G8-03이다. surrendered는 terminal이다.
- 연쇄 폭발은 target의 피해 전 최대 hull 40%, 다음 턴부터 2턴간 sensor -40%, 160×160 임시 위험 지대를 한 batch로 적용한다. 위험 지대는 movement 15000bp, observer sensor -15%, target concealment +8, weapon range 8500bp, arc -10°다.

정본 수치는 `data/red-cliffs-combat-effects-rules.json`이며 JSON statement와 이 문서가 같은 공식을 기록한다.

## 공개 projection

`viewer_combat_effects(viewer_faction_id)`는 자기 전대의 exact hull/composition/casualties/morale/sensor/capabilities를 제공한다. 적은 기존 visible contact의 `contact_id`, state, 공개 위치, 관측 label/band만 제공하며 raw squadron ID, 실제 위치, exact hull/morale/sensor는 내보내지 않는다. estimated contact의 실제 target 매핑은 core-only decoration으로 사용 후 제거한다. hidden/expired contact는 0행이다.

이벤트 row는 `{event_id,turn,event_type,viewer_state,own_squadron_id,contact_id,headline,details}`다. `viewer_state`는 `own|confirmed_contact|estimated_contact|public_hazard`다. 활성 임시 지형은 이 projection과 기존 `viewer_snapshot.terrain_zones` 양쪽에 동일한 viewer-safe zone으로 병합된다. `viewer_chain_explosion_state`는 `effects_resolved`와 `effects_status=applied|pending_resolution`을 제공한다.

## 저장 및 후속 경계

`combat_effect_state`는 battle snapshot 안에 original/current composition, hull, morale, sensor expiry, processed event IDs, temporary zones, events를 모두 보존한다. 공개 projection은 저장하지 않고 이 권위 상태에서 재구성한다. `victory_inputs`에는 세력별 잔존 hull/함선/사기/작전 가능 전대 수와 `winner_present=false`만 있다. 최종 승패는 DEMO-RC-G8-01, 실제 강제 퇴각·탈출점 결과는 G8-03 범위다.

## 검증 및 캡처

- G8 core: `PASS 112 / FAIL 0`
- public-flow UI: `PASS 35 / FAIL 0`
- 핵심 G4/G5/G6 회귀 17개: `PASS 1291 / FAIL 0`
- 집중 합계: `PASS 1438 / FAIL 0`, SCRIPT ERROR 0
- 독립 QA: P1 0 / P2 0

전체 `tests/run_tests.gd`는 sandbox의 기존 `user://` 저장 실패 뒤 `seed` 접근 오류가 이어져 `PASS 697 / FAIL 2`를 재현했다. G8 집중 시험과 관련 회귀에서는 같은 오류가 없으며 기능 실패로 집계하지 않는다.

1600×900 캡처는 `out/demo-rc-g8-00-combat-effects/combat-effects-1600x900.png`이고 SHA-256은 `38DA8C461B91BD92EC8623885848266CCF52EA127CF169FCA4B04BADECA82FA0`이다. 아군 exact 상태, 적 opaque 접촉 band, 센서 장애, 임시 위험 지대와 후속 G8-01 경계가 한 화면에서 판독된다. `out/`은 커밋하지 않는다.
