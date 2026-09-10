# DEMO-RC-G4-04 — 진형과 정면·측면·후면 보정

- Task ID: `DEMO-RC-G4-04`
- 공식/새 작업 제목: `DEMO-RC-G4-04 — 진형과 정면·측면·후면 보정`

## UI 계약

G4 턴 화면의 직접 지휘 전대 편집기에 코어가 허용한 진형만 선택하는 초안을 추가한다. 진형 허용 여부, 변경 성공/실패, 정면·측면·후면 sector, 보정 값은 모두 `allowed_formations`, `formation_order`, `set_formation_order`, `viewer_snapshot`, `viewer_turn_log`의 공개 결과만 소비한다. UI는 진형 데이터 파일을 직접 읽거나 각도·sector·보정 공식을 재계산하지 않는다.

- 직접 지휘 세력의 operational 전대만 진형을 변경할 수 있다.
- 전대 선택을 바꿔도 코어 command draft의 진형 선택이 유지된다.
- 허용 진형 7종은 한국어 이름·역할과 함께 제공하며 현재 진형과 변경 초안을 분리해 표시한다.
- HOLD/MOVE, waypoint 1~5, 방향, 손권 manual/AI/dont-ask와 동일한 원자적 제출 경계를 사용한다.
- 정면·측면·후면은 색만이 아니라 `정면`, `측면`, `후면` 문구로 표시하고 동일 좌표는 `방향 불명(동일 좌표)`로 표현한다.
- enemy unknown은 marker/event에서 계속 omit한다. estimated/stale은 last-known 접촉 외에 실제 facing·formation·sector·modifier를 공개하지 않는다.
- confirmed도 코어가 viewer에게 허용한 sector/modifier만 표시하며 예상 명령을 확정 상태처럼 보여주지 않는다.
- 피해·격침·승자는 후속 판정이며 만들지 않는다.

## 1600×900 정보 구조

좌측 단계/전대, 중앙 viewer-redacted 2D 지도, 우측 독립 스크롤, 하단 고정 원장/CTA라는 G4-03 구조를 유지한다. 진형 선택은 우측의 HOLD/MOVE 아래, 좌표·방향 위에 둔다. 현재 진형과 `변경 초안`을 분리해 취소 전 상태를 혼동하지 않게 한다. 지도 sector는 선택 전대 또는 코어가 공개한 이벤트에만 절제된 호/방향선으로 표시하며 범례를 둔다.

## 검증 체크리스트

- [x] allowed formation 7종과 profile modifier가 코어 snapshot과 일치한다.
- [x] 전대별 진형 변경/유지, 선택 전환, HOLD/MOVE 결합이 command draft에 보존된다.
- [x] 다른 세력/phase/programmatic 진형 변경이 원자적으로 거부된다.
- [x] resolve 시작에 진형 변경이 적용되고 same-turn effective 상태가 지속된다.
- [x] front/flank/rear/indeterminate 및 modifier 표시는 viewer event/snapshot 값만 사용한다.
- [x] unknown 및 estimated/stale 적의 actual formation/facing/sector/modifier가 지도·로그·tooltip·중첩 자료에 없다.
- [x] 피격 viewer는 적 사수의 range/distance/bearing/facing/arc를 재노출하지 않는다.
- [x] waypoint/zoom/pan/contact/fire overlay와 고정 CTA가 1600×900에서 유지된다.
- [x] headless/GPU 및 G4-03~G2 관련 회귀가 녹색이다.
- [x] 신규 경로의 3D 참조가 0이다.

## 시험 및 캡처

- G4-04 UI headless: `PASS 22 / FAIL 0`, exit 0
- G4-04 UI GPU: `PASS 24 / FAIL 0`, exit 0
- G4-04 core: `PASS 68 / FAIL 0`, exit 0
- G4-03 UI/core: `PASS 21 / FAIL 0`, `PASS 111 / FAIL 0`, exit 0
- G4-02 UI/core: `PASS 43 / FAIL 0`, `PASS 78 / FAIL 0`, exit 0
- G4-01 UI/core: `PASS 43 / FAIL 0`, `PASS 236 / FAIL 0`, exit 0
- G3 UI/core 및 G2: `PASS 62 / FAIL 0`, `PASS 135 / FAIL 0`, `PASS 77 / FAIL 0`, exit 0

GPU 캡처: `out/demo-rc-g4-04-formation-facing/formation-facing-1600x900.png`, SHA256 `8905146E812B573274E472D74EDF344838BD53B7A6E706B48C836CCDA34C76C5`. 1600×900에서 진형 현재/초안, 7종 picker, profile modifier, viewer-redacted 추정 접촉, 동일 좌표 sector 문구, 우측 독립 스크롤과 하단 고정 CTA를 확인했다. 실제 OS 물리 입력과 다수 이벤트 라벨 충돌은 후속 수동 QA 대상이다.
