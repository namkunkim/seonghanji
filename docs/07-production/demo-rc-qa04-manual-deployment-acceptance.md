# DEMO-RC-QA-04 — 수동 집결 전투 진입 독립 수용

## 범위와 독립성

이 수용은 구현 파일을 수정하지 않고 `tests/test_demo_rc_qa04_manual_deployment_loop.gd`에서 실제 `Main` 제품 장면을 기동한다. 시험은 `_start_red_cliff_demo()`와 가시 `Button.pressed`만 사용한다. 함대 위치, 도착 틱, manifest 참가자, 전투 상태·snapshot, 승패 및 뉴스는 직접 주입하지 않는다.

## 자동 수용 매트릭스

| 경로 | 확인 |
| --- | --- |
| 데모·시나리오 | 시작, Event 03/04/06/07 역사 Button, 시나리오 continue Button |
| 집결 | 홈의 `RedCliffDeploymentMission`, 대기 상태, `함대 선택` |
| 일반 이동 | 기존 `FleetMovePanel`의 RGN-04 선택과 `이동 요청`, `_on_fleet_move_requested()` 경로 |
| 시간·도착 | 가시 시간 바 재개 및 1×→2×→4×; Main의 `_process`로만 이동/도착 |
| 개전 | 이동 중 pending, SYS-13 실제 도착 뒤 active, 기존 개전 배너와 `전투 진입` |

## 실행 명령

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/test_demo_rc_qa04_manual_deployment_loop.gd
```

## 결과

2026-09-09 통합 후 headless 실행 결과는 **32 passed / 0 failed / exit 0 (PASS)** 이다. Godot 종료 코드는 `0`이 PASS, `1`이 FAIL이다. 환경의 `user://logs` 쓰기 및 Windows 루트 인증서 경고는 테스트 판정과 무관하며, 시험의 자체 종료 코드를 우선한다.

## GUI 캡처 목록

QA-04는 실 GUI 렌더러일 때 같은 제품 경로에서 아래 PNG를 `out/demo-rc-qa04-manual-deployment/`에 저장한다. headless CI는 렌더 타깃이 없으므로 캡처를 건너뛴다. Windows 사람 수용은 다음을 `out/`에만 저장하고 커밋하지 않는다.

1. 역사 선택 완료
2. 홈의 적벽 집결 임무
3. 손권 참가 함대 선택
4. RGN-04 이동 경로
5. 이동 중 상태
6. SYS-13 도착 상태
7. 적벽 개전 배너
8. 기존 전투 진입 화면

## 독립 QA 결론 및 남은 사람 스모크

독립 자동 제품 E2E 결론은 **PASS**다. 사람 스모크는 마우스·Tab·Shift+Tab·Enter·Space·Esc로 1600×900의 잘림/중첩, 버튼 포커스, Esc 홈 복귀, 도착 전 전투 진입 차단 및 도착 뒤 전투 진입을 확인한다.
