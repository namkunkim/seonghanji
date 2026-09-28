# DEMO-RC-G5-03 — 전장 지형의 이동·탐지·무기 효과

## 작업 식별

- Task ID: `DEMO-RC-G5-03`
- 공식 작업 제목/새 작업 제목: `DEMO-RC-G5-03 — 전장 지형의 이동·탐지·무기 효과`
- 화면 기준: 1600×900, 순수 `Control` 2D

## 범위와 권위

UI는 `RedCliffsTurnBattle`의 viewer-safe 공개값만 소비한다.

- `viewer_snapshot().terrain_zones`: 공개 AABB와 유형·이름
- `viewer_snapshot().own_terrain_membership`: 자기 전대 현재 체류와 코어 보정값
- `movement_preview().terrain_segments/terrain_events`: 자기 이동 초안의 구간·진입·이탈 결과
- `visible_tactical_events()`: 자기 전대 terrain event와 사수에게만 공개되는 `terrain_weapon_modifier`
- `detection_rationale.own_sensor_breakdown`: 자기 관측 전대의 terrain zone과 sensor modifier

UI는 AABB를 `battle_to_local()`로 변환해 그릴 뿐이다. 경계 포함, 중첩, 이동 비용, 탐지, 은폐, 무기 사거리·사격각 적용 순서와 반올림은 코어가 판정한다. `terrain_v4`와 외부 이미지/3D 자산은 참조하지 않는다.

## 정보 구조

- 중앙 지도: 성운·잔해 지대·행성 그림자를 반투명 면, 윤곽선, 한국어 유형과 이름으로 표시한다. 색만으로 구분하지 않는다.
- 이동 미리보기: 지형을 통과한 자기 경로 구간에 한해 코어가 준 zone ID, 이동 비용 bp, 탐지 %, 은폐 점수를 표시한다.
- 우측 지형 패널: 선택한 자기 전대의 현재 zone 이름과 현재 효과를 표시한다. 구역 밖도 명시한다.
- 전술 이벤트: 자기 전대의 진입·이탈·경계 접촉만 표시한다.
- 사격 이벤트: 자기 전대가 사수일 때만 코어의 지형 사거리 bp·사격각 보정·대상 소스를 표시한다. 추정 사격은 `봉인 추정 조준선`으로 표기한다.
- 탐지 근거: 자기 observer terrain만 표시하고 적 EW·적 terrain·정확 좌표는 비공개임을 명시한다.

미탐지 적의 위치·경로·zone 교차·체류와 적 효과는 렌더링하지 않는다. estimated fire는 봉인된 aim segment 결과만 소비하며 실제 표적 위치나 zone을 역산하지 않는다. hit, damage, winner는 이 작업 범위가 아니었다. G8-00은 같은 봉인 경계를 유지한 채 hit/damage와 임시 위험 지대를 후속 권위 상태에 연결했으며 winner는 G8-01에 남긴다.

## 검증

- G5-03 UI headless: `PASS 20 / FAIL 0`
- G5-03 UI GPU: `PASS 22 / FAIL 0`
- G5-03 core: `PASS 40 / FAIL 0`
- G5-02 UI/core: `PASS 20/0`, `PASS 67/0`
- G5-01 UI/core: `PASS 24/0`, `PASS 67/0`
- G4-07 UI/core: `PASS 22/0`, `PASS 59/0`
- G4-06 UI/core: `PASS 29/0`, `PASS 79/0`
- G4-05 UI/core: `PASS 30/0`, `PASS 80/0`
- G4-04 UI/core: `PASS 22/0`, `PASS 68/0`
- G4-03 UI/core: `PASS 21/0`, `PASS 111/0`
- G4-02 UI: `PASS 43/0`
- G4-01 UI: `PASS 43/0`

GPU 캡처: `out/demo-rc-g5-03-battlefield-terrain/battlefield-terrain-1600x900.png`

SHA-256: `558FD881756FF00DB030F1E06C2A2526F78A3A73E50A20CE1AF22DE8051C740F`

육안 확인 결과 중앙 지도, 우측 독립 스크롤, 하단 턴 원장과 고정 CTA가 1600×900 안에 유지된다. 세 지형 유형·이름과 아군 성운 진입/체류가 식별된다. 자동 Control signal로 제품 흐름을 검증했으며 실제 OS 물리 마우스의 장치별 감각 검증은 별도다.

## 후속 한계

- P2: 여러 zone과 5개 경유점이 동시에 있는 경우 지형 구간 설명이 길어지므로 접기/필터를 추가할 수 있다.
- P2: 지도 마커와 작은 zone 이름이 겹칠 때 label collision 회피를 보강할 수 있다.
- P2: 색각·고대비 환경을 위한 zone 채움 패턴 범례를 추가할 수 있다.
