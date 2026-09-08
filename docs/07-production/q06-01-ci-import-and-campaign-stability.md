# Q-06-01 — CI 필수 자산 추적 계약 및 캠페인 실행 안정화

Task ID: Q-06-01

공식 제목: CI 필수 자산 추적 계약 및 캠페인 실행 안정화

상태: PARTIAL

## 자산 계약 결론

`NotoSansKR-VF.ttf`와 P0-04 `ART-C901`~`ART-C911.png`는 Git 추적 파일이었다. 초기 Q-05 깨끗한 worktree 실패는 자산 누락이 아니라 Godot 4.7.2의 fresh-checkout import 순서 문제였다.

첫 editor pass는 filesystem metadata만 만들고 끝난다. 두 번째 quit 없는 editor pass가 실제 font/texture reimport를 예약한다. font cache가 생성된 뒤 깨끗한 worktree 단위시험은 35/35 섹션, 701 단언, 실패 0으로 통과했다.

`tools/ci/run_quality_gate.ps1`은 이 두 pass를 import 단계 안에서 수행하고, 필요한 font cache를 기다린다. cache 준비 뒤 P0-04 texture 안정화를 위한 15초 settling window를 둔 뒤 editor process tree를 종료한다. 모든 gate stage에는 300초 기본 timeout(import 180초)이 있으며 timeout은 stage FAIL로 기록되고 후속 stage를 막지 않는다.

## 남은 캠페인 문제

동일한 import 준비 뒤 `tests/run_campaign.gd`를 깨끗한 worktree에서 단독 실행했으나 시작 banner 뒤 유휴 상태가 재현됐다. 따라서 import race는 단위시험 실패를 설명하지만 campaign 유휴의 원인은 아니다. 실행기 timeout은 CI가 무기한 멈추는 것을 막지만 정상 exit 0을 대체하지 않는다.

다음 코어 진단 Task는 campaign 초기화/`run_to_end()`의 blocking 원인을 profile·seed 경계로 분리하고, 잠금 100회가 정상 종료하는지 검증해야 한다.
