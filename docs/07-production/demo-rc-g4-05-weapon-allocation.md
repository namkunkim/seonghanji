# DEMO-RC-G4-05 — 무기 비율·프리셋·사격 중지 명령

- Task ID: `DEMO-RC-G4-05`
- 공식/새 작업 제목: `DEMO-RC-G4-05 — 무기 비율·프리셋·사격 중지 명령`

## UI 계약

직접 지휘 세력의 operational 전대에 한해 코어가 제공한 무기 category, availability, preset, 정규화 allocation과 사격 보류 상태를 편집한다. UI는 합계·정규화·무기 가용성·기회 사격 가능 여부를 계산하지 않고 공개 command API의 receipt와 viewer-redacted snapshot만 표시한다.

- 무기 category별 요청 입력과 코어 정규화 결과를 구분한다.
- 정규화된 합계 `100%`는 코어 receipt/snapshot 값만 표시한다.
- 사용할 수 없는 category는 `사용 불가 · 0%` 문구와 disabled 상태를 함께 제공한다.
- 최소 3개 preset은 코어가 제공한 이름을 그대로 사용한다.
- `공격 보류`와 `사격 재개`를 명시적 두 상태로 제공한다.
- MOVE/HOLD, 진형 변경과 같은 command draft에서 전대별로 보존하고 원자적으로 제출한다.
- unknown/estimated/stale enemy의 allocation, preset, hold-fire, weapon capability를 지도·로그·tooltip에 노출하지 않는다.
- confirmed contact도 enemy allocation/hold-fire를 공개하지 않고 viewer event whitelist만 표시한다.
- 공격 보류는 사격 명령 경계일 뿐 명중·피해·탄약·열·격침·승자를 만들지 않는다.

## 1600×900 정보 구조

좌측 단계/전대, 중앙 redacted 2D 지도, 우측 독립 스크롤, 하단 고정 원장/CTA 구조를 유지한다. 무기 편집은 우측 진형 snapshot 아래의 `무기 운용 초안` 구역에 배치한다. category 입력은 44px SpinBox, preset은 키보드 접근 가능한 OptionButton과 적용 버튼, 공격 보류/재개는 색 외 상태 문구를 사용한다.

## 데이터와 API 권위

- 목록/상태: `weapon_categories()`, `weapon_presets()`, `viewer_snapshot().own_weapon_allocation_state`
- 전대 초안: `weapon_allocation_order(squadron_id)`
- 변경: `set_weapon_basis_points(...)`, `apply_weapon_preset(...)`, `set_hold_fire(...)`
- 사격 로그: 사수 viewer에게만 공개되는 `fire_control_snapshot`

UI는 basis point를 읽기 쉬운 백분율 문자열로만 변환한다. 합계, 잔여 배분, 자동 정규화, 가용성, 무기 선택, 사거리·사격각 적격 판정은 모두 코어 receipt/snapshot 값이 정본이다. 피격 viewer에는 `fire_control_snapshot`, 적 무기 ID와 배분을 표시하지 않는다.

## 검증 체크리스트

- [x] category·availability·preset 목록이 코어 공개 결과와 정확히 일치한다.
- [x] 요청값과 코어 normalized allocation/total이 구분되어 표시된다.
- [x] unavailable category는 0%·disabled이며 programmatic 변경도 코어가 거부한다.
- [x] preset 3종 이상 적용 결과가 receipt와 일치한다.
- [x] 공격 보류/재개가 같은 전대 command draft에서 지속된다.
- [x] MOVE/HOLD·진형·무기 초안의 동시 제출과 선택 전환 보존이 동작한다.
- [x] 다른 세력/programmatic 변경과 invalid allocation이 원자적으로 거부된다.
- [x] refresh가 allocation을 UI에서 재정규화하거나 사격 상태를 중복 변경하지 않는다.
- [x] enemy hidden/estimated redaction과 피격 viewer geometry 제한이 유지된다.
- [x] 1600×900에서 독립 scroll과 고정 CTA, 기존 waypoint/contact/sector UX가 유지된다.
- [x] headless/GPU 및 G4-04~G2 관련 회귀가 녹색이다.
- [x] 신규 경로의 3D 참조가 0이다.

## 시험 및 캡처

- G4-05 UI headless: `PASS 30 / FAIL 0`, exit 0
- G4-05 UI GPU: `PASS 32 / FAIL 0`, exit 0
- G4-05 core: `PASS 80 / FAIL 0`, exit 0
- G4-04 UI/core: `22/0`, `68/0`
- G4-03 UI/core: `21/0`, `111/0`
- G4-02 UI/core: `43/0`, `78/0`
- G4-01 UI/core: `43/0`, `236/0`
- G3 UI/core: `62/0`, `135/0`
- G2: `77/0`

GPU 캡처: `out/demo-rc-g4-05-weapon-allocation/weapon-allocation-1600x900.png`

SHA256: `65E4126B5C2BE587DC6F12DFABE4DEEFBA5BB903BECC5562028DC929350DC7AA`

육안 확인: 1600×900에서 좌측 전대, 중앙 2D 지도, 우측 무기 구역과 스크롤, 하단 고정 CTA가 겹치지 않는다. 현재 화면 높이에서 일부 category는 스크롤해야 하지만 모든 입력에 도달 가능하다.

## 한계와 후속

- P1 잔여 없음.
- P2: 실제 OS 물리 마우스·키보드와 고 DPI 환경은 자동 Control 입력/GPU 렌더 시험의 범위 밖이다.
- P2: 무기 category가 현재 4개보다 크게 늘어날 때의 장시간 스크롤 사용성은 별도 스트레스 시험이 필요하다.
