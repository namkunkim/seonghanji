# DEMO-RC-G4-06 — 제한 전투 자원과 결정론적 소모

- Task ID: `DEMO-RC-G4-06`
- 공식/새 작업 제목: `DEMO-RC-G4-06 — 제한 전투 자원과 결정론적 소모`

## 범위와 원칙

직접 지휘 중인 자기 전대의 제한 전투 자원과 코어가 확정한 소모·억제·회복 이벤트를 기존 2D 턴 화면에 표시한다. UI는 자원량, 비용, 소모 순서, 회복량, 과열·부족·미복귀 또는 사격 적격 공식을 계산하지 않는다. 명중·피해·격침·승패도 이 작업에서 만들지 않는다.

`normal-demo-resource-v1`은 적벽 데모 한정 규칙이다. 탄약과 특수 charge는 유한하며, 에너지는 회복하고 열은 냉각되며 함재기 준비도는 영구 손실 없이 복귀한다. 이는 전역 함선 제원의 글로벌 소모품 정본을 변경한 것이 아니다. 회복은 1턴에는 없고 2턴부터 각 턴 `resolve_turn` 시작에 정확히 한 번 적용되며, 선택 무기 자원이 부족하면 다른 무기로 대체하지 않는다.

적 전대의 자원, 무기 비용, 사격 억제 이유는 confirmed 접촉이라도 공개하지 않는다. 지도·로그·패널은 viewer 공개 API만 소비한다.

## 공개 API 권위

- 현재 상태: `viewer_snapshot(viewer_faction_id).own_combat_resources`
- 판정 시작 회복: `viewer_snapshot(...).resource_recovery_events`
- 소모·억제: `visible_tactical_events(viewer_faction_id)`의 `resource_consumed`, `fire_suppressed`
- 전체 authoritative 상태인 `combat_resource_state()`는 UI에서 사용하지 않는다.

자원 행은 코어가 준 현재/최대 값을 그대로 표시한다.

- 공유 자원: 에너지, 열
- 무기별 자원: 탄약, 함재기 준비, 특수 자원
- 소모 이벤트: 무기, 코어 비용, 전→후 상태
- 억제 이벤트: `reason_label`의 탄약 부족·에너지 부족·과열 한계·함재기 미복귀·특수 자원 부족
- 회복 이벤트: 판정 시작 턴과 전→후 상태

## 1600×900 정보 구조

좌측 단계/전대, 중앙 redacted 2D 지도, 우측 독립 스크롤, 하단 고정 원장·CTA 구조를 유지한다. 자원 패널은 같은 전대의 무기 배분 바로 아래에 배치해 명령과 결과의 관계를 가깝게 보여준다. 값은 색에 의존하지 않고 `현재/최대`, `전→후`, 명시적 한국어 사유로 표현한다.

## 검증 체크리스트

- [x] 자기 전대 에너지·열 현재/최대가 viewer snapshot과 일치한다.
- [x] 무기별 탄약·함재기·특수 자원 현재/최대가 viewer snapshot과 일치한다.
- [x] 적 자원은 confirmed 접촉에서도 패널·지도·로그에 나타나지 않는다.
- [x] 자원 소모 비용과 전후 상태는 사수 viewer에게만 나타난다.
- [x] 피격 viewer에는 적 `resource_reservation`과 자원 소모가 나타나지 않는다.
- [x] 다섯 가지 억제 사유는 코어 `reason_label`을 그대로 표시한다.
- [x] 턴 1에는 회복하지 않고 턴 2 판정 시작에 한 번만 회복한 receipt와 갱신 상태가 표시된다.
- [x] UI가 소모·회복·eligibility 공식을 복제하지 않는다.
- [x] 기존 무기 배분, waypoint, 접촉, 진형, 고정 CTA 회귀가 녹색이다.
- [x] 순수 Control/2D이며 신규 경로의 3D 참조가 0이다.

## 시험 결과

- G4-06 UI headless: `PASS 29 / FAIL 0`, exit 0
- G4-06 UI GPU: `PASS 31 / FAIL 0`, exit 0
- G4-06 core: `PASS 79 / FAIL 0`, exit 0
- G4-05 UI/core: `30/0`, `80/0`
- G4-04 UI/core: `22/0`, `68/0`
- G4-03 UI/core: `21/0`, `111/0`
- G4-02 UI/core: `43/0`, `78/0`
- G4-01 UI/core: `43/0`, `236/0`
- G3 UI/core: `62/0`, `135/0`
- G2: `77/0`

## GPU 캡처

- 파일: `out/demo-rc-g4-06-limited-resources/limited-resources-1600x900.png`
- SHA256: `51091D392E343FA634C7EF009F09EC22982C4FEB9EF5C2C75B306D57830F6A11`
- 육안 확인: 1600×900에서 지도·전대 목록·자원 현재/최대·턴 2 회복 전후 값·하단 CTA가 겹치지 않는다. 상세 자원과 이후 명령 입력은 우측 독립 스크롤로 접근 가능하다.

## 한계와 후속

- P1 잔여 없음.
- P2: 실제 OS 물리 마우스·키보드와 고 DPI 환경은 자동 Control/GPU 시험 범위 밖이다.
- P2: 무기 또는 자원 category가 크게 늘어날 때의 긴 스크롤 탐색성은 별도 스트레스 시험이 필요하다.
