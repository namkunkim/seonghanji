# DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프

- Task ID: `DEMO-RC-G4-01`
- 공식 작업 제목: `유비 명령·손권 제어 선택·20턴 판정 루프`
- 새 작업 제목: `DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프`

## 범위와 권위

이 단계는 G3에서 적용한 편성을 그대로 받아 20턴 명령 원장을 조작하는 순수 2D 제품 흐름이다. 턴·phase·손권 문의 정책·명령 검증·AI HOLD·턴 제한의 유일한 권위는 `core/demo_red_cliffs/red_cliffs_turn_battle.gd`의 public API와 deep-copy snapshot이다. UI는 이동, 무기, 탐지, 피해, 승패 규칙을 계산하지 않는다.

준비 화면은 current applied setup, `formation_revision`, setup JSON digest를 `battle_started` 단일 signal로 전달한다. Main은 최초 시작에만 코어와 화면을 만들며, 준비 화면으로 돌아갔다가 다시 시작하면 진행 중인 같은 전투 화면을 재표시한다. 이 범위에서는 진행 중 전투를 새 편성으로 교체하거나 초기화하지 않는다.

## 1600×900 정보 구조

- 상단: `적벽대전 · 턴 N/20`, 코어 phase의 한국어 설명.
- 좌측: 유비 명령 → 손권 제어 선택 → 손권 수동 명령 → 명령 원장 판정 → 승리 조건 판정 대기의 단계표.
- 중앙: applied setup의 전대 위치·세력·기함을 읽기 전용 2D 마커로 표시한다.
- 우측: 현재 직접 지휘 세력의 operational 전대와 `대기(HOLD)`를 표시한다. 이동·무기·진형 변경·탐지는 `후속 기능 · 현재 사용 불가` disabled 상태다.
- 하단: 턴 명령 원장, 상태 문구, 손권 문의 다시 켜기, phase별 주 CTA, 준비 화면 복귀.
- 손권 prompt: `이번 턴 직접 명령`, `이번 턴 AI 위임`, `AI 위임하고 더 이상 묻지 않음`의 세 버튼만 제공한다. 다시 묻지 않음은 AI 위임에만 결합된다.

## 흐름과 입력 경계

`liu_command → sun_control_prompt → sun_command 또는 AI → resolution → victory_check → 다음 턴` 순서다. 유비와 수동 손권의 CTA는 모든 operational 전대에 stable `hold` 명령을 제출한다. AI를 선택하면 코어가 손권·조조 stable AI HOLD를 만든다. UI는 `resolution`에서 `resolve_turn()`을 한 번 호출하고, receipt의 `rules_pending`만 로그에 표시한다.

CTA는 허용 phase에서만 동작하며 처리 프레임 동안 잠긴다. 같은 프레임의 더블 클릭, prompt 단계의 primary programmatic 호출, 이미 지난 phase의 재호출은 턴과 원장을 추가로 변경하지 않는다. 필수 prompt에서는 Esc가 화면을 닫지 않고 선택 필요 오류를 표시한다. 설정의 `손권 문의 다시 켜기`는 현재 전투 controller에만 적용된다.

Main의 `red_cliff_turn_battle_state`는 `active`, `turn`, `phase`, applied revision/digest, prompt policy, turn-log count를 노출한다.

## 비범위

- 이동, 사격, 진형 변경, 탐지, 피해, 사상자 계산
- 승리 조건과 승자 결정
- 3D 함선, GLB, 3D 항해·시네마틱
- 결과 화면과 전투 후 캠페인 반영
- 진행 중 전투에 새 적용 편성을 hot-swap하는 정책

20턴째는 `turn_limit_reached`와 `20/20 · 결과 판정 대기`만 표시하고 다음 턴을 금지한다. 승자·피해는 생성하지 않는다.

## 검증

- `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/test_demo_rc_g4_01_turn_battle_view.gd`: `PASS 44 / FAIL 0`, exit 0.
- 같은 시험의 Vulkan GPU 실행: `PASS 46 / FAIL 0`, exit 0. 추가 2개 단언은 1600×900 캡처 크기와 저장이다.
- G4 core: `PASS 236 / FAIL 0`, exit 0.
- G3 UI: `PASS 62 / FAIL 0`, exit 0.
- G3 core: `PASS 135 / FAIL 0`, exit 0.
- G2 회귀: `PASS 77 / FAIL 0`, exit 0. 전투 시작은 current applied setup/digest를 그대로 전달하고, 단일 G4 view 활성화와 초기 winner/damage 비생성을 확인한다.

캡처: `out/demo-rc-g4-01-turn-loop/turn-loop-1600x900.png`, 1600×900. SHA-256 `B6421B6E80926AAFEA634DDF632DF76763FBAE2E05251010C07880B717228B8A`. 육안 검토에서 한글 header·단계표·분리된 전대 마커·AI 전용 문의 억제 선택·44px 버튼·disabled 후속 기능·하단 로그가 화면 안에 있으며 modal 잘림이 없음을 확인했다.

실제 OS 물리 마우스 장치 입력은 수행하지 못했다. Godot Button signal과 Control focus 경로를 자동 조작했으며, 물리 포인터 좌표·DPI별 hit-test는 후속 P2 수동 확인 대상이다.
