# DEMO-RC-G4-02 — 자유 좌표·다중 경유점·방향 이동 판정

- Task ID: `DEMO-RC-G4-02`
- 공식 작업 제목: `자유 좌표·다중 경유점·방향 이동 판정`
- 새 작업 제목: `DEMO-RC-G4-02 — 자유 좌표·다중 경유점·방향 이동 판정`

## 범위와 단일 권위

턴 화면에 순수 2D 전술 지도와 전대별 HOLD/MOVE 편집기를 연결했다. 규칙과 상태의 단일 권위는 `RedCliffsTurnBattle`의 `movement_preview`, `live_navigation`, `current_direct_faction_id`, `command_order`, `command_draft_summary`, `set_order_hold`, `set_order_move`, `submit_command_draft`이다. UI는 거리, 속도, 예산, ETA 또는 도달점을 계산하지 않고 preview receipt를 그대로 표시한다.

충돌, 요격, 기회 사격, 무기, 탐지, 연료, 피해와 승패는 이 작업의 비범위다. 화면에는 무기·진형 변경·탐지만 `후속 기능 · 현재 사용 불가`로 비활성 표시하며 결과를 만들지 않는다. Node3D, GLB 및 3D 항해 참조는 없다.

## 정보 구조와 입력

- 좌측: 단계표와 현재 직접 지휘 세력의 operational 전대 목록. 다른 세력과 다른 phase는 programmatic 호출도 거부한다.
- 중앙: aspect-fit 전술 지도, 선택/경유점 추가/지도 이동 모드, 보기 초기화. live 위치 마커와 기함 표기를 보여준다.
- 우측: HOLD/MOVE, X/Y 좌표 대체 입력, 방향 0~359도, 번호가 있는 1~5 경유점, 중간 삭제·전체 초기화, 코어 preview의 거리/예산/ETA/예상 도달점.
- 하단: 스크롤과 무관한 상태·제출 CTA와 턴 원장. 제출은 기존 HOLD를 덮어 만들지 않고 코어 command draft 전체를 원자적으로 제출한다.

전장 `[x,y,w,h]`와 실제 map content rect 사이를 단일 aspect-fit 변환으로 왕복한다. zoom/pan은 같은 변환에 포함되며 letterbox와 전장 경계 밖은 거부한다. marker 클릭은 waypoint보다 먼저 소비한다. waypoint는 MOVE+추가 모드의 좌클릭만 받으며 drag/pan release는 추가하지 않고, wheel은 zoom만 수행한다. OS double-click의 두 번째 이벤트는 중복 waypoint를 만들지 않는다. Esc는 초안을 폐기하지 않는다.

경로는 live start부터 waypoint를 잇는다. 코어 `predicted_position`까지의 이번 턴 구간은 초록 실선, 이후 예산 밖 구간은 주황 점선과 문구로 구분한다. resolution 뒤에는 `live_navigation`으로 마커를 다시 그리며, 이동/부분 이동 건수를 movement receipt에서 턴 원장에 표시한다.

## 검증 결과

- G4-02 UI: `PASS 43 / FAIL 0`, exit 0 (headless)
- G4-02 core: `PASS 78 / FAIL 0`, exit 0
- G4-01 UI: `PASS 43 / FAIL 0`, exit 0
- G4-01 core: `PASS 236 / FAIL 0`, exit 0
- G3 UI/core: `PASS 62 / FAIL 0`, `PASS 135 / FAIL 0`, exit 0
- G2: `PASS 77 / FAIL 0`, exit 0
- GPU(Windows, Vulkan, Intel Arc): `PASS 45 / FAIL 0`, exit 0

집중 시험은 resize/zoom/pan의 corner·center roundtrip, letterbox 거부, marker/waypoint 충돌, click/drag/wheel/double-click, 1~5 추가·중간 삭제·초기화·6번째 원자적 거부, 전대별 초안 유지, facing/preview, phase·세력 권한, 단일 제출, 부분 이동 receipt와 live redraw를 확인한다.

캡처: `out/demo-rc-g4-02-movement/movement-ui-1600x900.png` (1600×900), SHA256 `1A8E4960C5F039EB146FE324E415F9CC3F6D06B364919A2DC3092D31EE8B9297`. 3열 목록/지도/명령 패널, 5개 waypoint, 경로 스타일, 고정 하단 CTA와 독립 스크롤을 육안 확인했다. 자동 Control 이벤트와 GPU 렌더링으로 검증했으며 실제 OS 물리 마우스의 장치별 감도는 별도 수동 QA 대상이다.

## 후속 한계

- P2: 실제 OS 마우스/키보드 전 구간 탐색과 고배율 DPI에서의 pan 감도 수동 QA.
- P2: 전대 수가 현재 데이터보다 크게 늘어날 때 목록 검색·필터와 경로 겹침 완화.
