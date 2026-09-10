# DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기

> Task ID: `DEMO-RC-G3-01`
> 공식 작업 제목: 비용 기반 전대·함대 편성 편집기
> 새 작업 제목: DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기
> 기준 환경: Windows, 1600×900, 마우스·키보드
> 범위: Phase A 전투 준비 편성. 턴 전투 실행과 3D 런타임은 포함하지 않는다.

## 1. 구현 범위

- 유비군은 직접 편집한다. 손권군은 사용자가 `연합 편성 수동 설정`을 켠 뒤 편집하며, 조조군은 항상 AI 읽기 전용이다.
- 역사 편성, 마지막 적용 편성, 현재 초안을 서로 독립된 깊은 복사로 유지한다.
- 편집기를 닫아 다시 열거나 같은 `Main` 인스턴스에서 준비 화면에 재진입해도 원본 역사 기준선과 현재 적용본을 분리해 유지한다.
- 기존 전대의 함종 수량, 고속정 임무 장비, 지휘관, 진형, 2D 초기 좌표를 편집한다.
- 함대를 생성·이름 변경하고 전대를 편입하거나 독립 전대로 전환한다. 빈 함대는 자동 정리한다.
- 함대 기함은 지휘관의 `command` 내림차순, `level` 내림차순, 안정적인 전대 ID 오름차순으로 자동 선정한다.
- 변경 취소와 역사 편성 복원은 초안만 바꾸며, 편성 적용에 성공할 때만 적용본과 revision을 한 번 갱신한다. 유효하지 않은 적용은 적용본 digest를 바꾸지 않는다.
- 초과 편성은 경고와 불이익을 표시하지만 재고·장수·전대·함대 등의 하드 불변식이 유효하면 적용할 수 있다.

## 2. 화면 정보 구조

| 영역 | 내용 |
|---|---|
| 상단 | 화면 제목, `normal-demo-v1`, 유비·손권·조조 권한 탭 |
| 왼쪽 | 함대와 독립 전대 목록, 새 함대 생성, 독립화, 함대 편입, 함대 이름 변경 |
| 가운데 | 지휘관·진형·좌표와 8개 함종 수량, 고속정 임무 장비 |
| 오른쪽 | 현재/권장 비용, 초과율·단계·불이익, 함종별 가용/총 재고 |
| 하단 | 검증·오류 상태, 역사 편성 복원, 변경 취소, 편성 적용, 편집기 닫기 |

손권 잠금과 조조 읽기 전용은 탭 문구와 비활성 입력을 함께 사용한다. 적용하지 않은 변경이 있으면 닫기를 막고 상태 문구로 다음 행동을 알린다.

## 3. 데이터와 API 권위

| 권위 | 경로 | 책임 |
|---|---|---|
| 초기 데이터 | `data/red-cliffs-demo-setup.json` | 세력 재고, 장수 command/level, 전대·함대, 함종 비용, 고속정 장비, 진형·좌표, 지휘 한도 규칙 |
| 문서 검증 | `core/demo_red_cliffs/red_cliffs_demo_setup.gd` | 알려진 ID, 정수·비음수, 정확 비용, 재고, 장수 유일성, 전대/함대 불변식 검증 |
| 편성 상태 | `core/demo_red_cliffs/red_cliffs_formation_draft.gd` | 역사/적용/초안, 모든 mutation, 비용·재고·초과 단계, 원자적 apply |
| UI | `scripts/red_cliff_turn/red_cliff_formation_editor.gd` | draft API 호출과 결과 표시 |
| 준비·Main | `scripts/red_cliff_turn/red_cliff_preparation_view.gd`, `scripts/Main.gd` | 원본 역사 기준선과 현재 적용본의 세션 수명, 성공한 적용본 요약 전달 |

UI는 공식 비용·재고 공식을 다시 구현하지 않는다. 권장 비용과 불이익은 `squadron_metrics()`, 세력별 총/사용/가용 재고는 `faction_inventory_summary()` 결과를 표시한다. 함종·장비의 척당 비용 표시는 초기 데이터의 설명 값이며 적용 가능성과 합계 판정의 권위가 아니다.

주요 draft API:

- 구성: `configure(historical_setup, applied_setup)`
- 조회: `historical_snapshot`, `applied_snapshot`, `draft_snapshot`, `applied_digest`, `draft_digest`, `squadron_metrics`, `faction_inventory_summary`, `summary`
- 편집: `set_ship_count`, `set_fast_equipment`, `set_commander`, `set_formation`, `set_position`, `set_sun_manual`
- 함대: `create_fleet`, `rename_fleet`, `assign_to_fleet`, `unassign_to_independent`
- 상태 전환: `restore_historical`, `cancel`, `validate_draft`, `apply`

## 4. 비용과 초과 불이익

전대 권장 비용은 다음과 같다.

`recommended = 40 + commander.command × 2`

실제 비용이 권장 비용보다 높을 때 다음으로 단계를 계산한다.

`over_ratio = (total - recommended) / recommended`
`tier = clamp(ceil(over_ratio / 0.25), 1, 4)`

단계당 불이익:

| 항목 | 단계당 | 4단계 최대 |
|---|---:|---:|
| 기동 | −5% | −20% |
| 명중 | −4% | −16% |
| 진형 변경 | −8% | −32% |

함종 비용은 `함종 수 × 척당 비용`이며 고속정은 선택한 임무 장비의 척당 비용을 더한다. `declared_total_cost`가 코어 계산값과 정확히 같아야 한다.

## 5. 검증 결과

### 자동 검증

| 시험 | 범위 | 결과 |
|---|---|---|
| `tests/test_demo_rc_g3_01_formation_draft.gd` | 데이터, mutation, 권한, 재고, 비용, digest, 함대, 기함, 초과편성, 역사/적용 수명 | `PASS 135 / FAIL 0`, exit 0 |
| `tests/test_demo_rc_g3_01_formation_editor.gd` headless | UI 구조, 입력 연결, 권한, 원자적 적용, 닫기·재진입 수명, Main 연동, 2D 경계 | `PASS 62 / FAIL 0`, exit 0 |
| `tests/test_demo_rc_g2_01_direct_preparation.gd` | G2 데이터·진입 회귀, 편집기 비파괴 진입 | `PASS 72 / FAIL 0`, exit 0 |

G2 비파괴 진입은 사용자 편성 버튼을 눌러 편집기를 열어도 `red_cliff_preparation_state`, applied revision과 applied digest가 바뀌지 않는지 확인한다.

### Windows GPU 화면

- 실행 장치: Intel Arc 130V, Vulkan Forward+
- 비-headless UI 시험: `PASS 64 / FAIL 0`, exit 0
- 캡처: `out/demo-rc-g3-01-formation-editor/formation-editor-1600x900.png`
- SHA-256: `CB9687A63D7F9FEDC272E69FB8A57D2132464CCDC7BE1FAF39C810769540F983`
- 육안 점검: 1600×900에서 잘림·겹침과 한글 깨짐 없음. 세 패널, 하단 작업 버튼, 유비·손권·조조 권한 문구를 식별할 수 있다.

`red_cliff_formation_editor.gd`와 `red_cliff_preparation_view.gd`에는 `Node3D`, `.glb`, `voyage_3d` 참조가 없다. `Main.gd`의 기존 3D 항해 경로 상수는 이 Task가 추가하거나 호출한 것이 아니며 G3 편성 경로 밖이다.

## 6. 독립 리뷰 결함과 처리

- **P1 — 함대 이름 변경 UI 누락:** 코어의 `rename_fleet()`만 있고 화면 조작이 없었다. 선택 함대 이름 변경 버튼과 UI 검증을 추가해 해소했다.
- **P1 — 역사/적용 상태 수명 혼합:** 편집기 재열기와 준비 화면 재진입이 현재 적용본을 새 역사 기준선으로 삼거나 기본값으로 초기화했다. `configure(historical_setup, applied_setup)` 분리와 Main 세션 적용본 보관으로 해소했다. 준비 화면의 `역사 편성 복원`도 역사 초안을 연 뒤 명시적 적용을 기다리는 흐름으로 연결했다.
- **P1 잔여:** 없음.
- **P2 — 시각 상태 표본:** 기본 유비 화면은 GPU로 확인했지만 손권 수동 설정 켜짐, 조조 읽기 전용, 초과 경고와 오류 상태의 별도 이미지 표본은 만들지 않았다. 기능과 문구는 자동시험으로 검증했다.

## 7. 한계와 후속

- `전투 시작`은 아직 턴 전투 엔진을 시작하지 않는다. Phase A는 검증된 적용본을 준비 상태에 전달하는 데서 끝난다.
- 전대 신규 생성·삭제와 드래그 앤 드롭은 이 범위에 없다. 기존 전대의 함종 수량을 0으로 만들 수 있지만 전대 전체는 최소 1척이어야 한다.
- 적용본은 같은 `Main` 런타임 세션에서 유지한다. 앱 재시작을 넘는 캠페인 저장 슬롯 영속화와 턴 전투 초기 상태 변환은 후속 Task가 소유한다.
- 실제 사용자 마우스 완주, OS 배율별 가독성과 보조기술 검수는 최종 Windows 수용 게이트에서 수행한다.
