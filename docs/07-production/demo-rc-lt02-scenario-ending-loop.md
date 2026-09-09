# DEMO-RC-LT-02 — 적벽대전 단편 시나리오 시작·분기·엔딩 플레이 루프

## 범위

`SCN-03` 적벽 데모는 새 Campaign에서 브리핑 후 Event 03·04·06·07의 정본 선택을
차례로 확정한다. UI는 `Campaign.scn03_demo_progression()`만 읽고
`issue_scn03_demo_choice()` 및 `continue_red_cliff_scenario_demo()`만 호출한다.
선택 결과, 참가 함대, 전투 스냅숏 또는 승패를 UI가 주입하지 않는다.

## 전이

모든 Event 09 조건이 true이면 Campaign이 Event 07 manifest와 그 manifest에 든
참가자의 정상 이동 명령을 기록해 기존 pending → active → 5 phase 흐름을 사용한다.
하나라도 false이면 battle을 만들지 않고 DEC-01에 따라 기존 종료 시점 판정을 즉시
사용한다. 선택·manifest·개전·결과는 모두 player-origin command log에서 재생 파생된다.

## 종료와 재시작

resolved 결과는 기존 canonical ActiveBattle 및 결과 적용/news 계약을 읽는다. 새 데모는
새 `SCN-03` Campaign을 만들므로 이전 선택, 전투, 뉴스와 결과 UI를 계승하지 않는다.
이는 C-01/C-02/C-03~05 또는 전체 G-07의 완료를 뜻하지 않는다.

## 검증

집중 core 25/0, 제품 진입 16/0, 독립 QA-03 91/0, 전체 core 701/701을 확인했다.
Windows 1600×900 GPU와 물리 Tab/Shift+Tab/Enter/Space/Esc 검수는 이 실행 환경에서
네이티브 Godot 창을 자동화할 수 없어 미완료이며 사람 스모크가 남는다.
