# G-10-UI-03 — canonical battle_id 기반 적벽 전투 화면 진입 셸

판정: **PASS** (2026-09-07)

`battle_entry_requested` 수신 경계는 display ID가 아닌 `SCN-03-E09-RED-CLIFF-01`만 허용하고, Campaign의 active canonical battle을 다시 조회한다. 셸은 홈 HUD·지도를 숨기고 전투 제목, 구지 궤도, 상태·phase·양측 함대 수를 표시한다. `천하도로 돌아가기`는 동일 홈 화면을 복원하며 셸은 단일 인스턴스로 재사용한다. display/unknown/resolved ID는 거부한다. 전투 시뮬레이션·phase 3~5는 범위 밖이다.

검증: `tests/test_red_cliff_battle_entry_shell.gd` 20/0, `tests/test_red_cliff_interrupt_banner.gd` 61/0 (Godot 4.7.2 console, exit 0). 독립 `gpt-5.6-terra / medium` 검수도 두 시험을 재실행해 PASS했다. 기존 `user://` 로그 및 certificate 경고만 발생했다.
