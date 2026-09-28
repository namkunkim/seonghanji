# DEMO-RC-G5-06 — 연쇄 폭발 작전 조건·방해·발동

## 범위

적벽 턴 전투 화면의 기존 2D 명령 패널에 연합 특수작전 자산의 준비도, 발동 예약, 발동 전 방해, 재시도, 불가역 발동 상태를 추가했다. 이 자산은 신규 함종이나 전대가 아니며, 손권군 제어가 수동인지 AI인지와 관계없이 유비 플레이어가 직접 작전 예약을 호출한다.

이 작업은 발동과 네 effect intent까지만 확정했다. 후속 G8-00에서 피해·사기·센서 장애·임시 지형 효과를 실제 상태에 원자 적용하고 화면 상태를 `효과 적용`으로 갱신했다. 일반 승리 판정은 계속 G8-01 대기다. 런타임 표현은 Control 기반 2D이며 Node3D, GLB, 영상 자산을 사용하지 않는다.

## 코어 권위와 상태 경계

- 준비 조건과 제한 증거는 `chain_explosion_readiness(contact_id)`의 receipt만 표시한다. UI는 사거리, 진형 집합, 성운 흐름, 요격 조건을 계산하지 않는다.
- 조작은 `stage_chain_explosion(detachment_id, contact_id)`와 `cancel_chain_explosion()`만 사용한다.
- 상태와 viewer별 공개 범위는 `viewer_chain_explosion_state(viewer_faction_id)`가 단일 정본이다.
- 상태 전이는 `idle → staged → disrupted | triggered`이다. `staged`는 resolve 시점에 최종 조건을 다시 검사한다. `disrupted`는 다음 유비 명령 턴부터 조건 재확보 후 재시도할 수 있다. `triggered`는 확률 판정 없이 확정되고 취소할 수 없다.

## 정보 구조와 접근성

오른쪽 명령 ScrollContainer 안에서 기존 명령과 고정 하단 CTA를 침범하지 않도록 다음 순서로 배치한다.

1. `연쇄 폭발 작전 · 연합 특수작전 자산` 제목과 텍스트 상태
2. 확인된 적대 접촉 목표 선택 버튼
3. 코어 condition 행: `충족`/`미충족` 문구, 이름, 공개 evidence
4. 최소 44px의 `작전 준비·발동 예약`, `준비 취소` 버튼
5. 발동 전 방해 가능성과 발동 후 취소 불가 경계

색상 외에도 모든 상태를 한국어 문구로 구분한다. 불충족·비권한·잘못된 phase에서는 버튼이 disabled이다. 손권 관점은 연합 작전 상태만, 조조 관점은 발동 전 정보를 전혀 보지 못한다. 발동 뒤 조조 관점에는 자기 피격 사실과 pending 효과만 공개되며 준비 조건과 staged 명령은 공개되지 않는다.

## 검증

- G5-06 UI headless: `PASS 48 / FAIL 0`, exit 0
- G5-06 UI GPU: `PASS 50 / FAIL 0`, exit 0
- G5-06 core: `PASS 70 / FAIL 0`, exit 0
- G5-05 AI core: `PASS 57 / FAIL 0`, exit 0
- G5-05 UI: `PASS 28 / FAIL 0`, exit 0
- G5-04 UI: `PASS 46 / FAIL 0`, exit 0
- G5-03 UI: `PASS 20 / FAIL 0`, exit 0
- G5-02 UI: `PASS 20 / FAIL 0`, exit 0
- G5-01 UI: `PASS 24 / FAIL 0`, exit 0
- G4-07 UI: `PASS 22 / FAIL 0`, exit 0
- G4-01 UI: `PASS 43 / FAIL 0`, exit 0

실제 battle 흐름에서 조건 미충족 잠금, 확인 접촉 선택, 준비·취소, 같은 조건 재준비, resolve 발동, 발동 후 취소 거부, viewer redaction을 검증했다. 별도 흐름에서는 AI 요격/조건 변화가 staged 작전을 `disrupted`로 전환하고 같은 턴 재시도를 막은 뒤 다음 유비 명령 턴에 재시도를 허용하는 것을 검증했다.

## 1600×900 GPU 확인

- 캡처: `out/demo-rc-g5-06-chain-explosion/chain-explosion-1600x900.png`
- 크기: 1600×900
- SHA-256: `F614EA1C2943898A31CCD4189ADD4AFF141D2A9097B1B84157998340C33B275E`
- 육안 결과: 전술 지도, 단계표, 턴 원장, 고정 진행 CTA가 유지되며 작전 제목·불가역 상태·pending 문구와 disabled 버튼이 오른쪽 독립 스크롤 영역에서 판독 가능하다.

자동 Control signal과 GPU 렌더로 검증했으며 물리 OS 마우스·키보드 장치 입력은 이번 시험 범위가 아니다.

## 후속 경계

실제 피해, 사기 충격, 센서 장애, 임시 지형 위험은 G8-00에서 구현되었다. 장수 사상자와 승패 판정은 아직 후속 범위다. 작전 전용 스틸 이미지나 음향 연출도 현재 범위에는 포함하지 않았다.
