# S5-02 — 적벽 실제 3D 전투 증거창 통합

## 승인과 범위

2026-09-13 사용자가 POC를 실제 성한지 코드에 반영하도록 명시 승인했다. 이 승인은 2026-09-09~10의 적벽 런타임 3D 임시 중단 정책을 S5-02 범위에서 상위 변경한다. B9, roadmap S5.2와 DECISIONS V-55/V-72가 상위 근거다.

실제 제품 진입은 `Main.gd → 적벽 준비 → 전투 시작 → RedCliffTurnBattleView`다. 기존 2D 전술 지도와 명령 UI는 canonical 조작 계층으로 남고, 3D는 같은 화면의 읽기 전용 공간 증거 계층이다. POC의 별도 미니게임, 1/2/3·WASD·Q/E 입력, 임의 HP, 무작위 일제사격은 반입하지 않는다.

## canonical projection 경계

코어의 `viewer_3d_projection(viewer_faction_id)`가 유일한 3D 입력이다. 이 DTO는 기존 `viewer_snapshot`, `viewer_combat_effects`, `visible_tactical_events`, 공개 가능한 `viewer_phase_ledger` metadata만 조합한다.

- 자기 전대: stable ID, 이름, 공개 세력, 기함 여부, 위치, 방향, 진형, 현재 편성, hull·사기·sensor·capability
- 적 접촉: opaque contact ID, confirmed/estimated 상태, 공개 display position, 관측 effect band/label만
- 전장: 공개 지형과 임시 위험 지대
- 사건: viewer-safe event를 turn/event ID/type 순으로 정렬하고 결정론적 visual seed와 순번 부여
- 금지: authoritative snapshot/receipt, raw enemy squadron ID, 실제 적 위치, 적 정확 함급·척수·HP·사기·sensor·방향·진형

자기 세력의 실제 이동 결과는 resolver의 전체 receipt를 전달하지 않고 `movement_resolved`의 stable event ID, own squadron ID, from/to endpoint만 새로 구성한다. DTO와 renderer 상태는 저장하지 않는다. 저장·복원과 replay 뒤 동일 core state에서 projection을 다시 만들며, 3D open/close·확대·frame 진행은 core digest를 바꾸지 않는다.

## 화면과 표현

중앙 전장은 기본 `2D 지도 2/3 + 3D 증거창 1/3` HSplit이다. `3D 크게 보기`는 비율을 1/3 + 2/3로 바꾸고 Esc는 2D 중심으로 복귀한다. 좌측 phase/전대, 우측 명령 scroll, 하단 원장/진행은 유지한다.

자기 전대는 공개 current composition 수만큼 실제 7종 모델과 고속정 glyph를 안정 순서로 배치한다. 상한은 204 visual instances이며 초과 시 stable composition order의 deterministic sampling을 사용하고 실제 숫자는 UI 계약에서 바꾸지 않는다. 확인·추정 적은 함급·척수·방향을 추정하지 않는 proxy다. 공개 event로만 이동 항적, 승인 사격선·피격, 보급/수리 halo, sensor/EW halo, 연쇄폭발·임시 위험 지대를 표시한다.

2D의 0°=`+X`다. 원본 GLB의 함수는 `-X`이며 model child yaw `-90°`로 런타임 local `-Z` 함수와 `+Z` 후미에 맞춘다. 전대 wrapper yaw는 `-(facing+90)°`다. 3D 증거창은 source POC보다 시각 크기를 1/3로 줄이고, 동봉 PBR material을 override하지 않는다.

## 자산과 성능

사용자 소유 원본은 `C:\WorkSpace\Re_Legend_of_the_Galactic_Heroes`다. 7개 GLB, 인접 PBR JPG 21개, 적벽 배경을 `assets/red_cliffs/visible_fleet_3d/v1/`에 격리했다. 파일별/집계 SHA-256, 원본 경로, 함종 mapping, 축과 재질 계약은 `visible_fleet_3d_manifest.json` 및 `PROVENANCE-LICENSE.md`가 정본이다. 고속정 SHP-08은 운송함으로 대체하지 않고 작은 절차적 glyph를 쓴다.

204척 초과는 stable sampling한다. 정적 projection은 변경 시에만 `SubViewport.UPDATE_ONCE`로 갱신한다. Compatibility는 동일 204척과 증거를 유지하면서 내부 560×436, MSAA off, shadow off를 사용하고 Forward+는 720×560, MSAA 2x다. 목표는 warm p95≤33.3ms, p99≤50ms다. 성능 영수증은 cold ready와 60-frame warmup 뒤 300-frame p50/p95/p99/max를 분리하고 renderer, display, GPU, Godot, viewport, projection SHA를 기록한다.

복구 후 최종 Intel Arc 130V/Godot 4.7.2 실측은 Forward+ cold 2886.213ms, p95 17.545ms, p99 17.748ms였다. Compatibility 실측은 cold 2612.641ms, p95 17.711ms, p99 18.406ms였다. 둘 다 목표를 통과했다. 영수증과 1600×900 캡처는 `out/s5-02-red-cliff-visible-fleet-3d/`에 두며 커밋하지 않는다.

## 검증과 수용

전체 코어 701/0, 저장·복원 73/0(+설계상 skip 2), 캠페인 replay 29/0, SCN-03 저장 replay 40/0이다. 독립 S5-02 집중 재실행은 projection 45/0, UI headless 34/0, UI Forward+ 38/0, stress headless 4/0, Forward+ 8/0, Compatibility 8/0으로 합계 137/0, SCRIPT ERROR 0이다. 최종 독립 QA는 P1 0, P2 0이다.

- [x] 실제 Main → 준비 → 전투 경로에서 3D 증거창이 나타난다.
- [x] 7종 모델, SHP-08 glyph, 함수/후미와 진형 배치가 projection과 일치한다.
- [x] 기본 2:1, 확대 1:2, Esc 복귀와 1600×900 비겹침을 확인한다.
- [x] hidden 적 node 0, estimated/confirmed opaque proxy, raw 적 정보 0을 확인한다.
- [x] 이동·사격·피격·보급·EW·연쇄폭발 표시가 viewer event를 넘지 않는다.
- [x] 저장·복원·replay와 반복 renderer 생성에서 core digest와 결정론을 보존한다.
- [x] 204척 cold/warm 성능과 두 GPU renderer 캡처를 기록한다.
- [x] 독립 QA P1/P2 0과 선택적 배포 경계를 확인한다.
