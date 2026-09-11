# DEMO-RC-G5-05 — 조조·손권 AI 동일 규칙·제한 자원 운용

## 작업 식별

- Task ID: `DEMO-RC-G5-05`
- 공식 작업 제목/새 작업 제목: `DEMO-RC-G5-05 — 조조·손권 AI 동일 규칙·제한 자원 운용`
- 화면 기준: 1600×900, 순수 `Control` 2D

## 공개 정보 구조

UI는 `viewer_ai_decision(viewer_faction_id, turn)`과 viewer 전술 API만 소비한다. 자기 AI 결정이 있는 viewer에만 다음 정보를 표시한다.

- 자세: 방어형 또는 압박형
- 의도 범주: 방어, 접적, 교전, 제한 교전, 자원 보존
- 코어가 제공한 한국어 선택 이유
- 자기 viewer에 공개된 접촉 신뢰도와 자기 자원 여유
- 손권·조조가 공유하는 코어 규칙 source (`normal-demo-ai-v1`)

UI는 AI 점수, threshold, 후보 정렬, 표적 선정, 자원 예약 또는 이동 공식을 계산하지 않는다. 현재 턴에 자기 AI 결정이 없으면 이를 명시하고, 다른 세력의 숨겨진 표적·명령·자원·능력치와 판단 내부값은 표시하지 않는다.

## Viewer 경계

- 손권 AI 위임 턴의 상세 명령과 의도는 손권 자기 viewer에서만 조회된다.
- 조조 AI 상세 명령과 의도는 조조 자기 viewer에서만 조회된다.
- 유비 viewer에는 손권·조조 AI receipt가 없으며, 탐지·이동·사격 등 기존 viewer-safe 전술 결과만 남는다.
- 수동 손권 턴에는 AI receipt를 만들거나 표시하지 않는다.
- 이전 턴 자기 AI 결정이 있고 다음 턴 직접 지휘로 전환된 경우, UI는 가장 최근 자기 AI receipt를 읽기 전용으로 설명할 수 있다.

## 기존 UX 보존

AI 패널은 우측 독립 스크롤 안에 있고 기존 이동·진형·무기·자원·지형·접촉·5단계 원장과 고정 하단 CTA를 변경하지 않는다. 자세와 의도는 색이 아니라 한국어 문구로 구분한다. 적 정보 redaction은 지도와 원장에서 그대로 유지된다.

## 검증 결과

- G5-05 UI headless: `PASS 28 / FAIL 0`
- G5-05 UI GPU: `PASS 30 / FAIL 0`
- G5-05 core: `PASS 57 / FAIL 0`
- G5-04 UI: `PASS 46 / FAIL 0`
- G5-03 UI: `PASS 20 / FAIL 0`
- G5-02 UI: `PASS 20 / FAIL 0`
- G5-01 UI: `PASS 24 / FAIL 0`
- G4-07 UI: `PASS 22 / FAIL 0`
- G4-06 UI: `PASS 29 / FAIL 0`
- G4-05 UI: `PASS 30 / FAIL 0`
- G4-04 UI: `PASS 22 / FAIL 0`
- G4-03 UI: `PASS 21 / FAIL 0`
- G4-02 UI: `PASS 43 / FAIL 0`
- G4-01 UI: `PASS 43 / FAIL 0`

G5-05 집중 시험은 손권·조조 own-only receipt, 동일 source, 자세·의도·이유·자원 여유 표시, 유비 viewer 누출 방지, 수동 손권 AI receipt 미생성을 검증한다. G5-02와 G4-07/G4-06의 과거 fixture 단언은 새 AI 이동·자기 자원 소비 계약에 맞춰 약화 없이 최신 redaction 기준으로 갱신했다.

GPU 캡처: `out/demo-rc-g5-05-ai-parity/ai-parity-1600x900.png`

SHA-256: `75B8B107C216D75B9A1AF147CFAA6A0F087F73ED7A60687D8AD578EB1BDAB6DE`

육안 확인 결과 1600×900에서 조조 자기 viewer의 AI 근거 제목, 압박형 자세, 동일 규칙 source, 접적 의도와 선택 이유, 자기 자원 여유, 비공개 안내가 우측 스크롤 안에 표시된다. 지도·하단 원장·고정 CTA는 잘리지 않는다. 자동 Control 전환으로 viewer redaction을 검증했으며 실제 OS 물리 입력의 장치별 감각 검증은 별도다.

## 후속 한계

- P2: 여러 전대의 AI 의도가 누적될 경우 전대별 접기와 범주 필터를 추가할 수 있다.
- P2: own AI replay viewer를 제품 메뉴로 제공할지는 별도 권한·관전자 정책에서 결정해야 한다. 현재 구현은 viewer-safe 컴포넌트만 제공하며 임의 faction 전환 UI를 만들지 않는다.
