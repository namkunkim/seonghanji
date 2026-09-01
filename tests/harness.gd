extends RefCounted

## 시험 하네스 공용 계약 (A-07 · docs/DECISIONS.md V-61 ④)
##
## 여기 상수 하나가 「시험이 조용히 사라지는 회귀」의 가드다.
## `run_tests.gd` · `run_campaign.gd` 가 preload 해서 쓴다.
##
##     const Harness := preload("res://tests/harness.gd")
##     quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

## 종료 코드 규약 — 통과 0 / 실패 비0. Q-05(CI 기준화)가 여기에 붙는다.
const EXIT_PASS := 0
const EXIT_FAIL := 1

## 단위 시험(`run_tests.gd`) 단언 수 하한.
##
## 2026-09-02 기준 정상 실행(`--import` 후) = 정확히 664.
## 이 값은 **하한**이다 — 실제 단언 수가 이보다 적으면 러너가 실패로 끝난다.
## 시험이 「통과」로 끝나도 단언 N개가 조용히 빠진 것을 잡는다.
##   예: `--import` 누락 시 섹션 34의 초상 PNG 가드(`if texture != null:`)가
##       단언 11개를 건너뛰어 664 → 653 이 된다. 그 회귀가 여기서 걸린다.
##
## ⚠ 시험을 늘리면 이 값도 함께 올린다 — 하한이 실제값을 바싹 따라가야
##    가드가 유효하다. 회귀 가드지 목표치가 아니므로, 의미 없는 단언으로
##    수를 채우지 않는다 (브리프 재론 금지 항목).
##
## ⚠ A-01(캠페인 저장 모델) 세션이 `tests/` 에 캠페인 재생 시험 케이스를
##    추가 중이다 (2026-09-02 세션 간 통지). 그 케이스가 커밋되면 단언 수가
##    664 위로 올라간다 — ≥ 가드라 그 자체로는 안 깨지지만, A-01 이 확정
##    델타를 보내면 이 값을 그만큼 상향한다.
const MIN_UNIT_ASSERTIONS := 664
