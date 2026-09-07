# G-10-UI-02 — 적벽 인터럽트 배너 Windows 1600×900 시각·입력 수용

판정: **PASS** (2026-09-07)

## 범위와 구현

- `scripts/Main.gd`는 HUD를 재구성할 때 이전 `CanvasLayer`를 해제하고 단일 소유 레이어만 만든다. 따라서 이전 적벽 배너 버튼이 남아 신호를 중복 발생시키지 않는다.
- `tests/test_red_cliff_interrupt_banner.gd`는 1600×900 viewport, 시간 표시줄 아래의 배너 위치·폭·1행 높이, canonical ID 경계, UI 재구성 후 단일 신호를 검증한다.
- `--visual-hold` 실행은 active phase 1 배너가 보이는 GPU GUI 화면을 캡처한다. `out/`은 커밋하지 않는다.

## 자동시험

다음은 모두 Godot 4.7.2 콘솔(`C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`)로 실행했다.

| 시험 | 결과 |
| --- | --- |
| `tests/test_red_cliff_interrupt_banner.gd` | 61 통과 / 0 실패, exit 0 |
| `tests/test_home_map_snapshot.gd` | 348 통과 / 0 실패, exit 0 |
| `tests/test_home_map_zoom.gd` | 175 통과 / 0 실패, exit 0 |
| `tests/test_home_submenu_routing.gd` | 347 통과 / 0 실패, exit 0 |

Godot의 `user://` 로그 생성 및 root certificate store 경고는 기존 환경 경고이며 위 시험 결과에는 영향을 주지 않았다.

## Windows 1600×900 시각·입력 판정

GPU GUI 실행(Vulkan, Intel Arc 130V)에서 viewport를 1600×900으로 고정해 확인했다.

- 배너: top/time bar 70px 바로 아래 `(196, 78)`, 중앙 safe content 폭 약 1091.2px, 높이 42px의 단일 행.
- 가독성: `적벽 전투 개전`, `전투 진입`이 읽히며 canonical/display ID는 화면에 노출되지 않는다.
- 경계: 좌·우 패널과 겹치거나 화면이 잘리지 않는다. 배너·행은 `MOUSE_FILTER_IGNORE`이고 버튼만 입력을 받는다.
- action: display ID `BATTLE-RED-CLIFF` 및 unknown ID는 거부하며, active phase 1 canonical battle ID에서만 신호 1회를 낸다. `stage:5`는 카메라 이동 경로로 유지된다.
- 재구성: 이전 HUD canvas를 해제한 뒤 재구성 버튼의 1회 입력은 신호 1회만 추가한다.

캡처: `out/g10-ui02-red-cliffs-banner-windows-acceptance/red-cliffs-banner-1600x900.png` — 1600×900, 1,069,749 bytes, SHA-256 `F304C9795BEA1E73D27BC38B603541F9687C67A50E2A728E734D07CA19BE3BC9`.

## 독립 검수

`gpt-5.6-terra / medium` 읽기 전용 검수는 전용 시험 61/0, 관련 코드와 위 캡처를 독립 점검하여 PASS 판정했다. 잔여 위험은 배너 외부 클릭 통과가 `MOUSE_FILTER_IGNORE` 및 자동 assertion으로 검증됐으며, 별도의 물리 마우스 dispatch 시험은 아니라는 점이다.
