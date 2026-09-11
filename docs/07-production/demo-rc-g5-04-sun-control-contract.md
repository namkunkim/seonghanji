# DEMO-RC-G5-04 — 손권 제어 문의 계약 재검증

## 작업 식별

- Task ID: `DEMO-RC-G5-04`
- 공식 작업 제목/새 작업 제목: `DEMO-RC-G5-04 — 손권 제어 문의 계약 재검증`
- 화면 기준: 1600×900, 순수 `Control` 2D

## 사용자 흐름

매 턴 유비군 명령 초안을 제출하면 현재 턴의 손권 문의 정책에 따라 다음과 같이 진행된다.

1. `이번 턴 직접 명령`: 손권군 전용 초안을 새로 열고 모든 operational 전대의 명령을 제출한다.
2. `이번 턴 AI 위임`: 현재 턴만 AI에 위임하고 다음 턴 다시 묻는다.
3. `AI 위임하고 더 이상 묻지 않음`: AI 위임과 함께 이후 문의를 끈다. 수동 지휘와 `더 이상 묻지 않음`을 결합하는 선택지는 없다.
4. `손권 문의 다시 켜기`: 현재 턴의 결정을 되돌리지 않고 다음 턴부터 문의를 복원한다.

문의는 `sun_control_prompt` 단계에서만 보인다. 전체 화면 입력 blocker가 배경 포인터 입력을 막고 첫 선택지에 포커스를 둔다. 세 버튼은 최소 44px이며 Tab/Shift-Tab 및 위·아래 방향 포커스가 세 선택지 안에서 순환한다. Esc는 창을 닫지 않고 한국어 이유를 표시한다.

## 상태 및 보안 경계

- 유비군 제출 뒤 유비 초안은 닫히고 수동 선택 시 별도의 손권 초안이 생성된다.
- 수동 손권 화면에서는 손권 전대만 raw own marker 및 직접 편집 대상으로 표시된다.
- 중복 CTA와 중복 prompt signal은 phase/busy guard로 같은 턴을 두 번 처리하지 않는다.
- 손권 prompt policy는 손권 viewer에만 공개되며 유비 viewer의 `prompt_policy`는 비어 있다.
- 지도·접촉·전술 이벤트는 viewer API 결과만 사용해 기존 전쟁 안개와 지형 redaction을 유지한다.

## 수정 사항

기존 중앙 prompt 패널 바깥에서 배경 포인터 입력이 통과하던 결함을 발견했다. `SunControlModalBlocker`를 추가해 prompt 활성 중 전체 화면 배경 입력을 차단했고, 세 선택지의 순환 포커스와 간결한 AI 전용 안내 문구를 추가했다.

## 검증 결과

- G5-04 UI headless: `PASS 46 / FAIL 0`
- G5-04 UI GPU: `PASS 48 / FAIL 0`
- G5-04 core: `PASS 180 / FAIL 0`
- G5-03 UI/core: `PASS 20/0`, `PASS 40/0`
- G5-02 UI: `PASS 20/0`
- G5-01 UI: `PASS 24/0`
- G4-07 UI: `PASS 22/0`
- G4-06 UI: `PASS 29/0`
- G4-05 UI: `PASS 30/0`
- G4-04 UI: `PASS 22/0`
- G4-03 UI: `PASS 21/0`
- G4-02 UI: `PASS 43/0`
- G4-01 UI/core: `PASS 43/0`, `PASS 236/0`

검증 항목은 실제 버튼 signal을 통한 manual/no/dont-ask, 다음 턴 재문의, 설정 재활성화, draft 격리, 포커스, Esc, 배경 차단, 중복 입력, viewer redaction을 포함한다.

GPU 캡처: `out/demo-rc-g5-04-sun-control-contract/sun-control-contract-1600x900.png`

SHA-256: `7A5E041538158D13DB185283BB32C69318CBA7EE107FC701B0C1EA1EF6CD3F9E`

육안 확인 결과 1600×900에서 중앙 prompt, 세 선택지, 설명 문구, 포커스 테두리가 잘리지 않는다. 배경은 시각적으로 비활성화되고 고정 CTA도 blocker 아래에서 조작 불가 상태로 식별된다. 자동 Control signal과 키 이벤트로 검증했으며 실제 OS 물리 마우스의 장치별 감각 검증은 별도다.

## 후속 한계

- P2: 스크린 리더용 prompt 역할·설명 연결을 명시하는 접근성 metadata를 추가할 수 있다.
- P2: 실제 키보드 장치에서 Shift-Tab 및 방향키 순환을 네이티브 입력 E2E로 보강할 수 있다.
