# 작업 트리 산출물 분류 감사 — 2026-09-07

## 관측 방법과 범위

- 2차 정정 시작 기준: 로컬 HEAD·`origin/main` 모두 `4518e05009bf22301af943d0df6f97d19a757b6a` (`main`, ahead/behind 0). 아래의 1차 감사 수치와 당시 기준선은 폐기된 관측값이며, 정확한 전수 재집계는 이번 정정 범위 밖이다.
- `git status --porcelain=v1`은 수정 9행과 untracked 디렉터리 286행, 합계 295행을 보였다. 디렉터리 축약 때문에 파일 수가 아니다.
- `git ls-files --others --exclude-standard`의 실제 untracked 파일 651개에 수정 9개를 더해, 아래 상호배타 분류 대상은 660개다. `git diff --name-status`도 수정 9개를 확인했다.
- 1차 등급별 파일 수 **A 54 / B 46 / C 511 / D 42 / E 7 = 660**은 확장자 기반 오분류(root GLB·`.codex/config.toml`·`.uid`·`.import`)를 포함하므로 폐기한다. 이번 정정은 전체 파일을 재집계하지 않으며 새 A~E 합계를 주장하지 않는다. ignored `.godot-appdata/` 95개와 `.godot/` 860개는 별도 C 런타임 캐시이며 총계에는 넣지 않았다.
- 이 문서는 보존·반입·보류 판단 증거다. 이 감사에서 파일 삭제, 이동, 복원, add는 하지 않았다.

## 경로별 분류

| 경로 또는 패턴 | 등급 | 파일 수 | 현재 참조 여부 | 보존 이유 | 후속 조치 | 삭제 가능 여부 | 소유권 또는 판단 근거 | 권장 커밋 묶음 |
|---|---:|---:|---|---|---|---|---|---|
| `assets/geography/natural-earth/`, `data/{fleets,home_systems,terrain_v4}.json`, `data/maps/{geography-layout,manifest}.json` | A | 9 | 일부 예 | 지리·게임 데이터 정본 후보 | 라이선스·생성 재현 확인 | 아니오 | `build_galaxy_map.py` 입력 및 world 문서 | `feat(map): geography inputs` |
| `tools/{build_galaxy_map,extend_galaxy_map,fetch_map_geography,map_model,map_model_v2,validate_galaxy_map,verify_galaxy_spatial}` 및 `docs/assets/{galaxy-detail-map.html,galaxy-detail-viewer.js,galaxy-map-data.js,galaxy-spatial*.js}` | A | 12 | 예 | 지도 생성 정본과 산출 연결 | builder→산출물 순서 검증 | 아니오 | HTML의 JS load 및 생성 스크립트 참조 | `feat(map): generated detail viewer` |
| `scripts/*.gd`, `shaders/*.gdshader`, `scenes/TerrainShaderTest.tscn`, `tests/capture_*3d.gd`, 수정 `docs/07-production/haemu-line-battleship-v3.md`, `docs/assets/star-map.html` | A | 33 | 부분 | terrain/shader·시험·문서 정본 후보 | main scene 연결과 실행 검증 | 조건부 | scene→script, `class_name`, 문서 링크 | `feat(terrain): authored terrain stack` / 문서 별도 |
| 수정 `assets/models/ships/{artillery_ship,assault_carrier,electronic_ship,siege_ship,supply_ship}.glb` | D/E 보류 | 5 | 직접 참조 아님 | `fleet_voyage_3d.gd`의 root 경로 상수는 미사용이며 실제 항행 로더는 `voyage_lod/`를 쓴다 | 출처·소유권·정본 여부 별도 판정 | 결론 전 금지 | B 직접 런타임 참조 오분류 정정; 삭제·복원·재수출 금지 | 별도 판정 |
| `assets/models/ships/`의 PBR JPG·필요 import, haemu V3 source/final texture·GLB, Wei 표준 모델 및 수정 `tests/verify_haemu_v3.gd` | B | 41 | 부분 | 런타임 자산 또는 검증 입력 후보 | 실제 선택 모델만 반입, tracked final LOD와 중복 확인 | 후보 외 조건부 | V3 final LOD GLB는 이미 tracked; 문서·검증기 참조 | `feat(haemu): v3 source+runtime asset` |
| `out/**`, `output/**`, 로그 및 검증 캡처 | C 후보 | 511에 포함됐던 1차 집계 | 대체로 아니오 | 재생성 가능 검증·캐시 산출물 | 필요한 캡처만 release evidence로 선별 | 조건부 | `.import`·`.uid`·`.codex/`를 이 행에서 일괄 C 처리했던 표현을 철회 | 기본 ignore; 필요 시 `test evidence` |
| `.codex/config.toml` | A | 1 | 예 | 프로젝트 오케스트레이터 정본 설정; `model = "gpt-5.6-terra"` | Git 추적 | 아니오 | 캐시가 아니며 `.codex/`의 다른 파일과 분리 | `chore(project): preserve model config` |
| `.uid` | 보존/보류 후보 | 1차 집계에서 45 | 대응 소스별 | 대응 `.gd`/`.gdshader` 등 소스가 있으면 Godot 식별자 보존 후보 | 대응 원본·경로별 판정 | 일괄 판정 금지 | 원본 없으면 orphan/보류, `out` 또는 명확한 임시 경로만 생성물 후보 | 별도 |
| `.import` | 보존/보류 후보 | 1차 집계에서 277 | 대응 자산별 | 런타임·승인 자산의 import 설정은 보존 후보 | archive 자산과 `out`/cache 재생성 파일을 경로별 분리 | 일괄 판정 금지 | archive는 별도 판정; `out`/cache 아래만 C 후보 | 별도 |
| ignored `.godot-appdata/**` (95), `.godot/**` (860), `tools/**/__pycache__`, `tools/tmp`, 로그 | C | 별도 | 아니오 | 로컬 Godot/Python 캐시 | commit 금지·ignore 유지 | 예 | `git status --ignored` | 없음 |
| `assets/concepts/**` raw, `assets/preproduction/**`, `data/maps/archive/{v1,v2}`, 구버전/review GLB·blend1, root `CONTEXT.md`, migration prompt, `setup_*.py`, `export_concept_glb.py`, `seonghanji-star-map.html` | D | 42 | 대체로 아니오 | provenance 또는 중복 후보 | 승인본·출처만 archive manifest로 보존 | provenance 확인 뒤 | archive 경로, v1/v2/v3·review 명명, 문서 참조 | `chore(archive): preserve provenance` 또는 제외 |
| `assets/models/ships/haemu_line_ship_lod0.glb`, `assets/reference_galaxy_map.png`, `tools/blender/build_wei_haemu_standard_battleship_v1.py`, `tools/capture_galaxy_preview.cjs`, `tools/open_{artillery,assault_carrier}_voyage_preview.gd`, 수정 `project.godot` | E | 7 | 불명/부분 | 소유권·정본/생성본 판단 보류 | 참조와 작성 의도 확인; `project.godot` renderer 설정의 malformed 주석/설정 복구 의도 확인 | 결론 전 금지 | 직접 참조 또는 출처를 확정하지 못함 | 별도 `fix(project): renderer setting` 후 판정 |

## 필수 자산 판정 요약

- root 함선 GLB 5종은 `fleet_voyage_3d.gd`의 미사용 경로 상수만으로 B 직접 런타임 참조로 오분류됐다. 실제 `_hero_glb_path()`는 `assets/models/ships/voyage_lod/{artillery_ship,assault_carrier,electronic_ship,siege_ship,supply_ship}.glb`를 사용한다. root GLB는 D/E 판정 보류이며 삭제·복원·재수출 금지다.
- `assets/models/ships/voyage_lod/**`는 실제 런타임 참조 B를 유지한다. 이번 정정에서 이 파일들은 수정하지 않는다.
- geography/지도 생성 체인은 A, terrain/shader 실험은 A 후보(미연결이면 후속 판정), concept/review/archive는 D다. `.uid`·`.import`는 확장자만으로 C 또는 삭제 가능이라 판정하지 않으며, `.godot-appdata`·명확한 `out`/cache 생성물만 C 후보다.
- E 7개와 다른 세션 소유 가능성이 있는 모든 dirty 자산은 삭제·이동·일괄 add 금지다.
