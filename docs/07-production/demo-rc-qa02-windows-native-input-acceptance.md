# DEMO-RC-QA-02 — 적벽대전 Windows 1600×900 네이티브 입력 수용

검수일: 2026-09-09

## 판정

**PASS — 실제 Windows 비콘솔 Godot, 1600×900, Vulkan Forward+ / Intel Arc 130V 8GB에서 40/40.**

`tests/test_demo_rc_qa02_native_input.gd`는 제품 `Main`을 그대로 만들고 내부 캠페인 상태를 주입하거나 제품 메서드·signal을 직접 호출하지 않는다. 화면에 보이는 버튼의 실제 전역 좌표로 `Input.parse_input_event` 마우스 press/release를 보내고, 전투 화면에서는 `Tab` 포커스 이동과 `Enter`로 AI 위임을 실행한다.

검증 흐름은 적벽 데모 시작 → 개전 배너 → 전투 진입 → 진형 유지 → 키보드 AI 위임 → 홈 → 화면의 1x→64x 제어 → 시간 재개 → 5페이즈 결착 → 결과 → 홈 복귀다. 단계별 1600×900 PNG 6장과 기계 판정 로그는 `out/demo-rc-qa02-windows-input/`에 있으며 `out/`은 커밋하지 않는다.

## 입력 경계

이 판정은 Windows 실제 GPU 네이티브 렌더러의 Godot 공개 입력 이벤트 경로를 수용한다. 현재 Computer Use 런타임은 네이티브 앱을 `apps: []`로 반환하므로 Windows 하드웨어 계층의 SendInput 자체는 자동화하지 못했다. 이는 제품 E2E PASS를 막지 않는 환경 제한으로 기록하며, 출시 전 사람의 물리 장치 스모크 항목은 별도 유지한다.

## 증거 파일

| 파일 | 바이트 | SHA-256 |
|---|---:|---|
| `01-demo-active-banner-1600x900.png` | 1,071,030 | `5CA77EFDB2D922B03506ACD6E4F4E93D16801D0B6B52BF8AAD374765AE7764D3` |
| `02-battle-entry-1600x900.png` | 536,990 | `C01506F58A5854D9C7570B22A67A7F22050C74501D480EE7A9816E9A58D352FE` |
| `03-hold-formation-1600x900.png` | 538,788 | `0E68B9568AB068AC961865BEAB31032C5A8EC47A490EFF09786AEBD759B13BB1` |
| `04-ai-delegated-1600x900.png` | 539,215 | `975208CC22B22F6518E3891565DA920D8D1FDC59AE2D6BA9DA44203A2035C239` |
| `05-five-phase-result-1600x900.png` | 1,065,729 | `9441CF090FCC64C98E9C964462CC4EE61A68D3A4A0EDC13751941966B582EA8F` |
| `06-home-after-result-1600x900.png` | 1,065,734 | `DC481A09458AF3A429BD48867D6F1DAB33BFC1F73DBC3084E996FCB899A2073C` |

기계 판정 원문은 `qa02-native-input-report.txt`이며 최종 결과는 **40 passed / 0 failed**다.
