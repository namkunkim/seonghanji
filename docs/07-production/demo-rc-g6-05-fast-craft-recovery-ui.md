# DEMO-RC-G6-05 — 표류·구조·나포와 나포 보급함 무력화

## 읽기 전용 표시 계약

전투 UI는 `viewer_fast_craft_recovery(viewer_faction_id)`만 소비해 표류·구조·나포 상태, 명령 capability, viewer-safe 이벤트와 나포 보급함 무력화를 표시한다. incident 카드에는 `자동 판정 · 읽기 전용`을 명시하며 수동 구조·나포 버튼이나 mutation 경로가 없다. 직접 지휘와 AI는 같은 코어 resolver·validator를 사용한다.

자기 고속정은 상태, 연료, 표류 시작 턴·방향, responder와 `command_locked`, `can_move`, `can_attack`, `can_change_mission`을 정확히 표시한다. 잠긴 전대는 좌측 목록에서 `· 잠금`으로 남아 상태 카드를 다시 열 수 있지만 지도 명령 target과 편집 가능 전대에서는 제외된다. HOLD/MOVE, 좌표·방향, 진형, 무기, 추정 사격, 전술 임무와 귀환 조작도 같은 capability에 맞춰 disabled된다. 코어 public mutation은 이 잠금을 다시 검증한다.

표류 전 저연료 MOVE 미리보기는 코어 `movement_preview()`의 `fuel_limited`, `requested_total_distance`, `predicted_actual_distance`, `maximum_fuel_distance`, `available_fuel_basis_points`, clamp된 `predicted_position`, `path_complete=false`, `eta_turns=-1`을 그대로 표시한다. UI는 `요청 거리 → 예상 실제 / 최대`, 가용 연료, 예상 정지점과 `실제 판정과 동일`을 명시한다. 집중 테스트는 405 bp에서 300.0 거리 요청이 40.5로 제한되고 예상 정지점 `(740.5, 700.0)`이 실제 resolve 이동 거리·도달점과 일치함을 검증한다.

구조 responder는 불변 `FAST-EQ-RESCUE` 장비와 활성 `rescue` 임무를 가진 비표류 아군·연합 고속정뿐이다. resolved event의 `responder_route`와 `target_route`를 그대로 2D 지도에 그리며 접촉·거리·우선순위를 UI에서 계산하지 않는다. 보급함은 구조 responder가 아니라 authoritative 나포 시 무력화되는 대상이다.

## 정보 경계

| viewer 상태 | UI 공개 | 비공개 |
|---|---|---|
| own | 정확한 ID·위치·연료·상태·잠금·자기 responder/event | 없음 |
| confirmed | 코어가 확인한 contact와 정확한 전대 ID·위치·관측 상태 | 연료·자기 전용 capability·숨은 responder 경로 |
| estimated/lost | contact ID, 추정 위치, error radius·confidence·staleness, 추정 상태 | 실제 전대 ID·실제 위치·raw target/responder route |
| hidden | 행·이벤트·지도 marker 없음 | 모든 recovery 정보 |

UI는 `viewer_state`를 `확인` 또는 `추정`으로 명시한다. 적 관측 행에는 private fuel이 없고, estimated 행은 `squadron_id`가 비어 있다. hidden responder의 ID와 경로, estimated target의 실제 ID·경로는 코어에서 제거된 receipt만 사용한다.

## 보급함 무력화와 범위 경계

정상 보급함의 근접만으로 나포가 발생하지 않는다. 내부 `_apply_authoritative_supply_capture` fixture는 `authority=G8-00`, `status=authorized_capture`인 권위 intent만 수용한다. 성공 시 해당 SHP-05 source는 활성 G6-03 보급 영역에서 원자 제거되고 `capacity_squadrons_per_turn=0`, `captor_gain=0`으로 표시된다. 같은 턴 refill에서 제외되며 captor에게 재고나 신규 source를 주지 않는다.

실제 damage/boarding trigger는 G8-00 경계다. 나포 즉시 잔여 재고 폐기·captor gain 0과 손상 처리량·거점 재적재는 G6-06에서 구현했으며, 포획 보급함의 수리·재사용은 허용하지 않는다. 화면은 `Control` 기반 2D 전용이며 G6-04의 공통 라벨 충돌 회피를 재사용한다.

## 검증

- G6-05 core: `PASS 93 / FAIL 0`
- G6-05 UI headless: `PASS 67 / FAIL 0`
- G6-05 UI GPU: `PASS 71 / FAIL 0`
- G6-04 core/UI 회귀: `PASS 46 / FAIL 0`, `PASS 42 / FAIL 0`
- G6-03 core/UI 회귀: `PASS 53 / FAIL 0`, `PASS 39 / FAIL 0`
- G6-02 core/UI 회귀: `PASS 154 / FAIL 0`, `PASS 53 / FAIL 0`
- G4-02 core/UI 회귀: `PASS 78 / FAIL 0`, `PASS 43 / FAIL 0`
- G4-06 core/UI 회귀: `PASS 79 / FAIL 0`, `PASS 29 / FAIL 0`
- G5-01 core/UI 회귀: `PASS 67 / FAIL 0`, `PASS 24 / FAIL 0`
- G5-05 core/UI 회귀: `PASS 57 / FAIL 0`, `PASS 28 / FAIL 0`

직접 실행한 headless 집중·회귀 합계는 `PASS 952 / FAIL 0`이다.

GPU 캡처: `out/demo-rc-g6-05-fast-craft-recovery/fast-craft-recovery-1600x900.png` (1600×900, 145,712 bytes), SHA-256 `FE6A811377889AE0ECF473919B91A1226CB4508209071E1434157929FEB81651`.

저연료 미리보기 캡처: `out/demo-rc-g6-05-fast-craft-recovery/fast-craft-fuel-preview-1600x900.png` (1600×900, 127,251 bytes), SHA-256 `B0FCF67BFF22161033B0B04FFDFE558F018609EA921AA35F2A93BB571F0655AF`.

캡처는 T2 유비 viewer에서 좌측 목록의 잠금 전대, 지도상의 표류 이중 ring과 연료 0 라벨, 나포 보급함의 X·처리 0/턴 표시, 읽기 전용 카드의 이동·공격·임무 잠금, G8-00/G6-06 경계를 함께 보여 준다. 라벨 겹침과 숨은 적 정보는 없다.

저연료 캡처는 T1에서 원 경유점과 40.5 거리 clamp 정지점을 지도에 구분하고, 패널의 요청 거리 300.0, 예상 실제·최대 40.5, 가용 연료 405 bp, 예상 정지 좌표와 ETA 산출 불가를 보여 준다.
