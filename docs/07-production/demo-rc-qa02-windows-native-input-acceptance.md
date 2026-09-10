# DEMO-RC-QA-02 — 적벽대전 Windows 1600×900 GPU 공개 입력 경로 수용

> **최신 상태(2026-09-10 · `MGMT-HANDOVER-01`): 과거 구현 기준선 증거.** 기존 AI 위임·5페이즈·홈 복귀 입력 흐름은 최신 유비 중심 턴제 데모의 Windows 수용을 대신하지 않는다.

검수일: 2026-09-09

## 판정

**PASS — 실제 Windows 비콘솔 Godot, 1600×900, Vulkan Forward+ / Intel Arc 130V 8GB에서 47/47.**

`tests/test_demo_rc_qa02_native_input.gd`는 제품 `Main`을 그대로 만들고 내부 캠페인 상태를 주입하거나 제품 메서드·signal을 직접 호출하지 않는다. 화면에 보이는 버튼의 실제 전역 좌표로 `Input.parse_input_event` 마우스 press/release를 보내고, 전투 화면에서는 `Tab` 포커스 이동과 `Enter`로 AI 위임을 실행한다.

검증 흐름은 적벽 데모 시작 → 개전 배너 → 전투 진입 → 진형 유지 → 키보드 AI 위임 → 홈 → 화면의 1x→64x 제어 → 시간 재개 → 5페이즈 결착 → 결과 → 홈 복귀다. 단계별 1600×900 PNG 6장과 기계 판정 로그는 `out/demo-rc-qa02-windows-input/`에 있으며 `out/`은 커밋하지 않는다.

## 입력 경계

이 판정은 Windows 실제 GPU 렌더러에서 Godot 공개 입력 이벤트 경로를 수용한다. Win32 `SendInput`이나 물리 마우스·키보드를 시험한 것은 아니다. 현재 Computer Use 런타임은 네이티브 앱을 노출하지 않으므로 하드웨어 계층은 자동화하지 못했고, 출시 전 사람의 물리 장치 스모크 항목을 별도 유지한다.

## 증거 파일

| 파일 | 바이트 | SHA-256 |
|---|---:|---|
| `01-demo-active-banner-1600x900.png` | 1,070,828 | `AFF137B8DBC0090609A9700F3531301C64DB498B0AC4F1EA5D039F5BEE8EB7FD` |
| `02-battle-entry-1600x900.png` | 578,714 | `5EF74CE13B92007686AFD91E7473D93E437B917A89112C36AAF761F1899E78A5` |
| `03-hold-formation-1600x900.png` | 579,429 | `EF448000EE6480D9D36902A3375A4CAEE2F50020200D2E26708FA80A28967A2D` |
| `04-ai-delegated-1600x900.png` | 579,113 | `E0EBD732B9056C9EE19E6E7F748C022BF7013759247A1C5045EC04E7515581E8` |
| `05-five-phase-result-1600x900.png` | 1,065,544 | `4F62C4E4E0CF2C7FCB39AC6F6504571568313E63A4B16A9E305AFDC4581D5D5F` |
| `06-home-after-result-1600x900.png` | 1,065,719 | `FCDEC4FDC3288B28B92205E5FB579837D09EFC531AE93084F7168C22A3254562` |

기계 판정 원문은 `qa02-native-input-report.txt`이며 최종 결과는 **47 passed / 0 failed**다.
