# G-10-QA-01 — 적벽 개전부터 전투 화면 진입까지 E2E 검증

판정: **PASS** (2026-09-07)

기능 E2E는 개전 조건→pending/active battle→canonical 뉴스/배너→전투 셸→홈 복귀→동일 셸 재진입을 검증한다. Godot 4.7.2 console headless 실행은 24/0, GPU GUI(Vulkan/Intel Arc 130V) 캡처 실행은 36/0으로 통과했다. 독립 `gpt-5.6-terra / medium` 검수도 동일 두 실행을 재검증해 PASS했다. `user://` log, certificate 및 shader-cache 경고는 시험 실패가 아니다.

캡처는 커밋하지 않으며 `out/g10-qa01-red-cliffs-entry-e2e-acceptance/`에 있다. 모두 1600×900이다.

| 파일 | bytes | SHA-256 |
| --- | ---: | --- |
| `01-active-banner-1600x900.png` | 1,070,290 | `cddf6fdf2ef45ba1aaea4f87a235c545b0643917953c88d784e9d0611ce164ea` |
| `02-entry-shell-1600x900.png` | 29,659 | `8af429b109c62644d8dba07b4754c73a4e054ec77e5e3193bb30089c5d070d29` |
| `03-home-return-1600x900.png` | 1,070,047 | `e1f78d28e98a77d70ee2491eb2d6fd2da66b47e025e6cb2a82e817f1a228dbdd` |
| `04-reentry-shell-1600x900.png` | 29,659 | `8af429b109c62644d8dba07b4754c73a4e054ec77e5e3193bb30089c5d070d29` |

재진입 셸은 동일 canonical 상태라 02와 04의 bytes/hash가 의도적으로 같다.
