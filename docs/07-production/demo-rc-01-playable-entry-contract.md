# DEMO-RC-01 — 적벽대전 플레이어블 데모 진입 계약

`Main._start_red_cliff_demo()`는 UI 상단의 **적벽** 버튼에서 호출하는 제품 경로다.
고정 입력은 `SCN-03`, master seed `20803`, 그리고 정본 Campaign API로 기록한 Event 03·04·06·07 결과, participant manifest, 구지(`RGN-04`) 도착 명령이다.

이 경로는 private field, battle snapshot, 테스트 fixture를 주입하지 않는다. Campaign reducer가 canonical `SCN-03-E09-RED-CLIFF-01`을 pending으로 만들고 participant 도착 후 active phase 1로 전환한다. 같은 입력은 같은 명령 로그, battle ID, 초기 digest를 만든다.

활성화 뒤 시간은 정지한다. 따라서 플레이어는 홈 지도, 개전 뉴스, 인터럽트 배너를 확인하고 전투 화면으로 진입할 수 있다. 저장은 Campaign의 seed + command-log 계약을 사용하며, 재생으로 동일 active 시작 상태를 복원한다.

자동 검증은 `tests/test_demo_rc_01_playable_entry.gd`가 데모 시작, pending→active, 개전 뉴스 exactly-once, canonical ID 및 저장·복원을 검사한다.
