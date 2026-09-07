# G-10-UI-04 — 적벽 전투 화면 상태 표시 및 홈 복귀 경계

판정: **PASS** (2026-09-07)

전투 셸은 canonical battle ID, 적벽/구지 궤도 위치, active 상태, phase, 공격·방어 세력과 함대 수를 읽기 전용으로 표시한다. 홈 복귀 및 재진입은 동일 셸을 재사용하며 canonical battle 상태를 변경하지 않는다. display·unknown·resolved ID는 거부한다.

`test_red_cliff_battle_entry_shell.gd` 29/0과 `test_red_cliff_interrupt_banner.gd` 61/0이 Godot 4.7.2 console에서 exit 0으로 통과했다. 독립 `gpt-5.6-terra / medium` 검수도 동일 시험을 재실행해 PASS했으며, `Campaign.to_save_dict()`가 진입·복귀·재진입 전후 동일함을 확인했다. 기존 user log/certificate 경고만 있었다.
