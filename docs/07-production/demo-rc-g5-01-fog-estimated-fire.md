# DEMO-RC-G5-01 — 전쟁 안개·마지막 확인·추정 사격

- Task ID: `DEMO-RC-G5-01`
- 공식/새 작업 제목: `DEMO-RC-G5-01 — 전쟁 안개·마지막 확인·추정 사격`

## 범위와 정보 경계

viewer 공개 API만 사용해 unknown, estimated/lost, confirmed 접촉을 구분하고 직접 지휘 중인 유비 또는 수동 손권 전대가 estimated 접촉에 추정 사격 초안을 설정·취소할 수 있게 한다. 탐지, 접촉 수명, 오차, 조준점, 사격 적격, 무기 선택과 결과는 UI에서 계산하지 않는다.

- unknown과 만료 접촉: 지도·목록·tooltip·원장에 완전히 나타나지 않는다.
- estimated: opaque `contact_id`, last-known 위치, 마지막 확인 턴, 경과 턴, 신뢰 basis point, 오차 반경, 만료 턴과 불확실성 문구만 표시한다.
- lost/stale: last-known 정보만 표시하며 추정 사격 선택은 허용하지 않는다.
- confirmed: 현재 위치 재확인으로 표시하고 estimated 선택을 해제한다. 편성·명령·자원 등 공개되지 않은 정보는 추가하지 않는다.

만료된 접촉은 과거 `last_seen_turn`이 남아 있어도 전술 이벤트나 원장을 통해 다시 나타나지 않는다. age 3의 lost 접촉까지만 opaque viewer 접촉으로 유지한다.

## 공개 API 권위

- 접촉: `visible_contacts(viewer_faction_id)` 및 `viewer_snapshot(...).contacts`
- 초안 조회: `estimated_fire_order(squadron_id)`
- 설정/취소: `set_estimated_fire(squadron_id, contact_id)`, `clear_estimated_fire(squadron_id)`
- 제출 수: `command_draft_summary().estimated_fire_count`
- 판정 표시: `visible_tactical_events`와 `viewer_phase(..., "barrage")`

UI는 코어가 봉인한 `last_known_position`, 전장 경계 안으로 제한된 `aim_position`, `error_offset`, `error_radius`, `confidence_basis_points`를 그대로 표시한다. 실제 표적 좌표, 적 전대 ID, 편성, 명령은 읽거나 추론하지 않는다. AI 손권·조조의 추정 사격은 이 범위에서 생성하지 않는다.

## 조작과 1600×900 IA

- 지도: estimated 접촉은 점선 원과 `실제 좌표 아님` 문구로 표시한다. 선택 시 외곽 선택 링을 추가한다.
- 대체 입력: 우측에 번호 기반 `추정 접촉 N 선택` 버튼을 제공해 마우스 지도 클릭에만 의존하지 않는다.
- 초안: `추정 사격`과 `추정 사격 취소`를 44px 버튼으로 제공한다. 조준점·오차·신뢰와 `명중/피해 pending`을 명시한다.
- 원장: 포화 단계에 코어가 공개한 `estimated_fire_authorized` 또는 `estimated_fire_suppressed`와 pending만 표시한다.
- 기존 우측 독립 스크롤과 하단 고정 CTA를 유지한다.

## 검증 체크리스트

- [x] 전투 초기 unknown 적은 지도와 viewer snapshot에서 완전히 숨는다.
- [x] estimated 접촉은 actual ID/현재 위치 없이 last-known 공개 위치만 사용한다.
- [x] 수명·신뢰·오차·만료 값이 viewer contact와 정확히 일치한다.
- [x] 지도 선택과 키보드 접근 가능한 대체 버튼이 같은 opaque contact를 선택한다.
- [x] 추정 사격 설정·취소·재설정이 core draft API와 일치한다.
- [x] core 봉인 aim/error를 표시하며 UI가 오차를 계산하지 않는다.
- [x] 결정론적 오차 aim은 코어가 전장 경계 안으로 제한하고 같은 봉인 검증을 적용한다.
- [x] confirmed 접촉은 재확인 문구로 구분되고 estimated 선택이 유지되지 않는다.
- [x] 다른 세력·AI·lost/unknown/expired contact의 programmatic 변경은 코어가 거부한다.
- [x] 포화 원장은 estimated fire event와 weapon_fire/hit/damage pending만 표시한다.
- [x] hit/damage/승자를 과장하거나 생성하지 않는다.
- [x] 1600×900 지도·원장·스크롤·고정 CTA가 겹치지 않는다.
- [x] 기존 G4 명령 UX 회귀와 2D/3D 금지 경계가 유지된다.

## 시험 결과

- G5-01 UI headless: `PASS 24 / FAIL 0`, exit 0
- G5-01 UI GPU: `PASS 26 / FAIL 0`, exit 0
- G5-01 core: `PASS 67 / FAIL 0`, exit 0
- G4-07 UI/core: `22/0`, `59/0`
- G4-06 UI/core: `29/0`, `79/0`
- G4-05 UI/core: `30/0`, `80/0`
- G4-04 UI/core: `22/0`, `68/0`
- G4-03 UI/core: `21/0`, `111/0`
- G4-02 UI/core: `43/0`, `78/0`
- G4-01 UI/core: `43/0`, `236/0`
- G3 UI/core: `62/0`, `135/0`
- G2: `77/0`

## GPU 캡처

- 파일: `out/demo-rc-g5-01-fog-estimated-fire/fog-estimated-fire-1600x900.png`
- SHA256: `2F30336DAA2526D57301DADE53534010632E289AD6E30BB6AFBB08E5CC07A895`
- 육안 확인: estimated 접촉이 점선과 `실제 좌표 아님` 문구로 구분되고, 포화 단계에는 추정 사격 억제 event와 hit/damage pending만 보인다. 다섯 단계, 중앙 지도, 우측 스크롤과 하단 CTA가 겹치지 않는다.

## 한계와 후속

- P1 잔여 없음.
- P2: 실제 OS 물리 입력·스크린리더·고 DPI는 자동 Control/GPU 시험 범위 밖이다.
- P2: 동시 estimated 접촉이 크게 늘어날 때의 목록 검색·그룹화는 후속 스트레스 대상이다.
