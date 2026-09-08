# DEMO-RC-05 — 적벽 결과 적용과 캠페인 복귀

5페이즈 결착은 `ActiveBattle`의 계산 결과로만 resolved된다. UI에는 승자·손실·사기를 쓰는 경로가 없으며, `Campaign._apply_red_cliff_result_once()`가 참여 함대의 최종 함선 수·사기를 한 번만 투영한다. 권역 소유권은 변경하지 않는다.

resolved transition news ID는 canonical battle ID와 `resolved` 토큰에서 파생된다. Campaign 저장은 snapshot이 아니라 명령 로그를 재생하므로, 결과 적용 및 뉴스는 저장·복원에도 중복되지 않는다. 전투 화면은 결착 결과를 관찰한 뒤 홈으로 복귀하며, resolved canonical battle의 재진입은 거부된다.

`tests/test_demo_rc_qa01_e2e.gd`는 결과 적용, 결과 뉴스 exactly-once, 저장·복원, 홈 복귀와 resolved 재진입 거부를 제품 경로로 검증한다.
