# DEMO-RC-02 — 적벽 지속형 5페이즈 전투 코어

## 계약

`SCN-03-E09-RED-CLIFF-01`만 지속형 전투다. 일반 조우전의 즉시 해결기는
변경하지 않는다. 전투 정본은 저장 스냅숏이 아니라 시드와 player-origin 명령
로그의 재생이다.

페이즈는 `접적 → 포화 → 교전 → 강습 → 결착` 순서만 허용한다. 접적은 활성화한
다음 tick에 결정론적으로 포화로 전이하며, 이후에는 한 명령 또는 AI 위임 tick이
정확히 한 페이즈만 계산한다. 이미 기록한 페이즈, 건너뛴 페이즈, resolved 뒤
명령은 거부된다.

## 공개 명령 API

`Campaign.issue_red_cliff_player_command(battle_id, kind, payload={}, delay_ticks=0)`
가 유일한 제품 명령 입구다. `kind`는 `hold_formation`,
`change_formation` (`target_formation_id` 필요), `advance_phase`, `delegate_ai`다.
손실·사기·계략·승자를 받는 인수는 없다. UI는
`red_cliff_command_state(battle_id)`의 `accepted`, `reason`, `phase`, `status`,
`can_advance`, `can_change_formation`, `ai_delegated`를 표시한다.
`can_advance`는 자동 접적 중인 phase 1에서는 false이고 phase 2부터 true다.
AI 위임 뒤에는 진행·진형·유지·재위임을 포함한 플레이어 전술 입력을 잠근다.

## 계산과 상태

`ActiveBattle`은 각 측 현재 함선·사기·진형, phase 시작/종료 tick, 페이즈 결과,
적용 계략, player command/AI decision 기록, 최종 결과를 보유한다. 계산은
`Battle`의 fixed-point 전력/손실/사기 함수, `Formations`의 전투 판정,
`Scheme`의 성공 확률을 재사용한다. 계략 굴림은 battle ID·phase·tick으로 파생한
combat RNG 키를 사용하므로 UI 순서와 무관하게 재생된다.

함선 0 또는 사기 0은 해당 페이즈의 collapsed 사실로 기록한다. 데모는 항상
결착 화면까지 보이도록 phase 5에서만 최종 승자를 전력과 사기로 계산한다.

## 결과 적용 및 재생

결착 결과는 `campaign_result_applied`로 보호해 참가 함대의 현재 척수·사기를
정확히 한 번만 투영한다. 권역 소유권은 바꾸지 않는다. resolved news ID는
`SCN-03-E09-RED-CLIFF-01:resolved`로 안정적이며 replay에서도 같은 로그에서
한 번 파생된다.

`Save.CURRENT_RULESET`은 `RS-0.5.0`이다. 명령 구조가 변조되면 검사 단계에서
부분 복구하고, 구조상 유효하지만 결과를 바꾸는 변조는 campaign digest 검증이
실패한다.

## 자동 검증

`tests/test_scn03_red_cliff_phase_result.gd`는 활성화, 1→2 자동 전이,
2→3→4→5 명령 전이, 계산 결과, resolved exactly-once, save/replay digest,
명령 구조 변조 및 중복 결과 로그를 검증한다.
