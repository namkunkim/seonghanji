# Q-06-01 — CI 필수 자산 추적 계약 및 캠페인 실행 안정화

Task ID: Q-06-01

공식 제목: CI 필수 자산 추적 계약 및 캠페인 실행 안정화

상태: PASS

## 자산 계약 결론

`NotoSansKR-VF.ttf`와 P0-04 `ART-C901`~`ART-C911.png`는 Git 추적 파일이었다. 초기 Q-05 깨끗한 worktree 실패는 자산 누락이 아니라 Godot 4.7.2의 fresh-checkout import 순서 문제였다.

첫 editor pass는 filesystem metadata만 만들고 끝난다. 두 번째 quit 없는 editor pass가 실제 font/texture reimport를 예약한다. font cache가 생성된 뒤 깨끗한 worktree 단위시험은 35/35 섹션, 701 단언, 실패 0으로 통과했다.

`tools/ci/run_quality_gate.ps1`은 이 두 pass를 import 단계 안에서 수행하고, 필요한 font cache를 기다린다. cache 준비 뒤 P0-04 texture 안정화를 위한 15초 settling window를 둔 뒤 editor process tree를 종료한다. 모든 gate stage에는 300초 기본 timeout(import 180초)이 있으며 timeout은 stage FAIL로 기록되고 후속 stage를 막지 않는다.

## 캠페인 시간 계약

`run_campaign.gd`는 표준 잠금 ruleset 100회만 실행하는 파일이 아니다. 본 실행 뒤 HB 자유/표준/역사중시의 3×100회 비교를 수행하므로 전체는 **400회** 시뮬레이션이다. 중간 진행 출력이 없어 배너 뒤 조용한 것이 정상이었다.

격리 `RUNS=1` probe는 본 실행 1회와 HB 비교 3회를 1.221초에 완료했고, 모든 구조 검증 경로가 끝까지 실행됨을 확인했다. 따라서 Q-05의 110초 중단은 hang 증거가 아니라 충분하지 않은 관찰 시간이었다. quality gate는 campaign stage timeout을 **900초**로 설정해 정상 400회 실행을 허용한다. job 전체 timeout 30분은 유지한다.
