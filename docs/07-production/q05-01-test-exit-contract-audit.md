# Q-05-01 — 시험 실행 계약 및 종료 코드 감사

Task ID: Q-05-01
공식 제목: 시험 실행 계약 및 종료 코드 감사

기준 실행기는 `tools/ci/run_quality_gate.ps1`이며, Godot 4.7.2 stable headless와 import를 선행한다. 각 필수 항목은 실패 시 `1`, 정상 시 `0`이다. 공통 `tests/harness.gd`는 PASS=0/FAIL=1 및 단위시험 최소 단언 수(701)를 정의한다.

| 시험 | 목적 / 구조 가드 | 예상 시간 | 정상·실패 종료 | 입력·출력·SKIP | CI |
|---|---|---|---|---|---|
| `run_tests.gd` | 코어 단위시험, 35 섹션·701 단언 하한 | <15초 | 0 / 1 | import된 class cache 필요; 콘솔 요약 | 포함 |
| `run_campaign.gd` | 잠금 ruleset AI 캠페인 100회 | 30~120초 | 0 / 1 | 데이터·결정적 seed; 지표 요약 | 포함 |
| `run_campaign_replay.gd` | 저장 전/재생 후 digest | <30초 | 0 / 1 | `user://` 임시 저장; 콘솔 요약 | 포함 |
| `run_save_restore.gd` | 저장·복원/변조/결정성 | <45초 | 0 / 1 | 쓰기 가능한 `user://`; 의도된 snapshot SKIP 1건 | 포함 |
| `verify_power.gd` | 국력·권역 합계 정본 대조 | <10초 | 0 / 1 | 게임 데이터; 기대/실제 불일치 목록 | 포함 |
| `verify_budget.gd` | 수입·행정·잔여 정본 대조 | <10초 | 0 / 1 | 게임 데이터; 항목별 대조표 | 포함 |
| `verify_chibi.gd` | 적벽 페이즈/계략 정본 대조 | <10초 | 0 / 1 | Battle/Scheme; 기대/실제 불일치 목록 | 포함 |
| `verify_glyphs.gd` | 임베드 폰트·app 문자 범위 | <15초 | 0 / 1 | import된 폰트; 누락/경고 출력 | 포함 |
| `test_a05_formation_combat.gd` | A-05 진형 집중 계약 | <15초 | 0 / 1 | 코어 데이터; 단언 요약 | 포함 |
| `test_g10_qa01_red_cliffs_entry_e2e.gd` | G-10 적벽 진입 E2E | <45초 | 0 / 1 | 헤드리스 씬; 단언 요약 | 포함 |

`verify_power.gd`와 `verify_chibi.gd`는 과거에는 대조표만 출력하고 성공 종료할 수 있었다. Q-05-02부터는 모든 항목을 검사하고 불일치를 누적한 뒤 실패 종료한다. 저장 관련 시험은 실행기가 격리한 쓰기 가능한 `APPDATA`/`LOCALAPPDATA` 기반 `user://`를 사용한다. Godot 4.7.2 Windows에는 `--user-data-dir` 옵션이 없으므로 이 방식이 필요하다.
