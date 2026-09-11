# DEMO-RC-G5-02 — 센서·전자전·진형·장수 탐지 보정

- Task ID: `DEMO-RC-G5-02`
- 공식/새 작업 제목: `DEMO-RC-G5-02 — 센서·전자전·진형·장수 탐지 보정`

## 범위와 원칙

코어가 제공한 viewer-safe `detection_rationale`만 사용해 자기 관측 전대의 센서·진형·지휘 보정과 최종 접촉 상태의 근거를 한국어로 표시한다. 적 전대의 EW 수치·함종·지휘관·진형, 실제 거리, score·margin·threshold는 UI와 viewer payload에 노출하지 않는다.

UI는 센서 점수를 합산하거나 탐지 수식·threshold를 복제하지 않는다. 탐지는 수동 command가 아니라 코어 자동 판정이며, 기존 `탐지 후속 기능` 버튼은 `탐지 · 자동 코어 판정 · 수동 조작 없음` 안내로 교정한다.

G3 편집기에서 선택 가능한 demo roster의 character ID는 `characters.json`의 이름과 정확히 일치해야 한다. 조운·관우·노숙·조인·하후돈의 초기 잘못된 ID를 canonical ID로 교정해, 예비 지휘관을 적용한 setup도 이 탐지 초기화 경계를 통과한다.

## Viewer-safe 스키마

contact와 detection event가 공유하는 `detection_rationale`을 그대로 소비한다.

- `result_state`, `reason_code`, `reason_label`
- `observer_formation_id`, `observer_formation_detection_percent`
- `own_sensor_breakdown`
  - `ship_sensor_points`, `formation_adjusted_sensor_points`
  - `commander_id`, `commander_name`
  - `intelligence_band`, `intelligence_sensor_points`
- `terrain_status: pending_neutral`
- `terrain_label: 지형 보정 대기(중립)`
- `rules_pending: [terrain_detection]`

적 EW는 코어 내부 판정에만 사용하며 UI에는 `적 EW 수치 비공개` 경계를 명시한다. 지형은 0·중립이며 G5-03 구현 전까지 결과로 오인하지 않도록 pending을 함께 표시한다.

## 1600×900 IA

기존 접촉 정보 바로 아래에 두 줄 이상의 탐지 근거를 표시한다.

- 접촉 상태와 last-known 불확실성
- 코어 `reason_label`
- 자기 함선 센서 → 코어가 제공한 진형 적용값
- 자기 지휘관 이름, 지력 구간과 센서 점수
- 관측 진형 ID와 탐지 보정
- 적 EW 비공개, 지형 G5-03 pending

우측 독립 스크롤을 사용하며 G5-01 추정 사격, G4-07 원장과 하단 고정 CTA를 유지한다. 값은 색에 의존하지 않는다.

## 검증 체크리스트

- [x] viewer contact와 detection event가 같은 safe rationale을 제공한다.
- [x] 자기 함선 센서·진형 적용값이 코어 payload와 일치한다.
- [x] 자기 지휘관 이름·지력 구간·보정값이 코어 payload와 일치한다.
- [x] 관측 진형 ID·탐지 보정을 UI가 재계산하지 않고 표시한다.
- [x] 적 EW·적 편성·적 지휘관·적 진형 raw 값이 없다.
- [x] 실제 거리, score, margin, confirmed/estimated threshold를 표시하지 않는다.
- [x] 지형은 `pending_neutral`, `terrain_detection`, G5-03 대기로 표시한다.
- [x] 탐지 control은 자동 판정 안내이며 가짜 수동 command가 아니다.
- [x] G5-01 estimated contact·추정 사격 UI가 유지된다.
- [x] 피격 viewer는 적 사격 geometry를 재노출하지 않는다.
- [x] 1600×900 스크롤·지도·고정 CTA가 겹치지 않는다.
- [x] 제품 코드 3D 참조가 0이다.

## 시험 결과

- G5-02 UI headless: `PASS 20 / FAIL 0`, exit 0
- G5-02 UI GPU: `PASS 22 / FAIL 0`, exit 0
- G5-02 core: `PASS 67 / FAIL 0`, exit 0
- G5-01 UI/core: `24/0`, `67/0`
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

- 파일: `out/demo-rc-g5-02-detection-modifiers/detection-modifiers-1600x900.png`
- SHA256: `47F4205BF59ED6F393949A19686D4390C66073727C2EFA7E03928DB878BB41F3`
- 육안 확인: 우측에서 estimated contact의 lifecycle과 탐지 근거, 자기 센서·진형·지휘 보정, 적 EW 비공개와 지형 pending이 함께 읽힌다. 지도·추정 사격·원장·하단 CTA가 겹치지 않는다.

## 한계와 후속

- P1 잔여 없음.
- P2: 실제 OS 물리 입력·스크린리더·고 DPI는 자동 Control/GPU 시험 범위 밖이다.
- P2: 동일 좌표에 여러 전대와 접촉이 겹치는 시험 fixture에서는 지도 표식 설명문이 서로 겹친다. 상태·선택은 유지되지만 후속 label 배치/클러스터링 개선이 필요하다.
- G5-03에서 실제 지형 보정을 구현할 때 `terrain_status/label/rules_pending` 계약을 교체해야 한다.
