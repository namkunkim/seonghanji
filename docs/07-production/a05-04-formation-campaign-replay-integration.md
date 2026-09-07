# A-05-04 — Campaign·UI·AI·저장 재생 통합

상태: PASS (2026-09-07)

`Campaign.formation_verdict_for_fleet`은 UI·AI·재생 소비자가 읽는 단일 읽기 전용 공용 투영이다. 일반 전투는 기존 공용 `Battle`/`Formations` 경로를 사용한다. G-10은 phase 1~2에서만 이 투영을 표시하며 새 상태·전술 UX·phase 3~5는 만들지 않았다. `scripts/Main.gd`는 이름과 코어의 `combat_milli`만 표시하고 계산식을 중복하지 않는다.

검증: A-05 집중 93/0, 적벽 entry shell 29/0, 전체 core 35/35·701/0. 기존 저장 지문은 formation command/terrain 상태를 포함해 재생 비교를 유지한다.
