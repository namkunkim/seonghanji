# DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용 UI

## 표시 계약

편성 UI는 `RedCliffsFormationDraft.squadron_metrics()` 공개 영수증만 표시한다. 현재/권장 비용, 초과 단계, 기동·명중·진형 변경 수치와 각 소비 상태를 UI에서 다시 계산하지 않는다. 세 불이익은 다음 코어 소비 지점에 연결된다.

- 기동: G4 이동 유효 속도
- 명중: 실제·추정 사격의 자원 소모 전 유효율 snapshot
- 진형 변경: 해결 시작 시 변경 턴 modifier 유효율

전투 UI는 `viewer_command_penalty_metrics(viewer_faction_id, squadron_id)`와 viewer-safe 전투/원장 이벤트만 사용한다. 자기 전대에는 현재 단계와 세 불이익을 표시하며 수동 명령과 AI 명령이 동일한 코어 판정을 사용한다고 밝힌다. 적 전대의 비용, 단계, 명중 수치는 표시하지 않는다.

## 명령 결과

진형 변경 이벤트의 `modifier_effectiveness_basis_points`를 그대로 표시한다. 1~4단계 변경 턴 유효율은 각각 92%, 84%, 76%, 68%이며, 같은 진형을 유지하는 다음 턴에는 100%로 복귀한다.

실제 및 추정 자기 사격 이벤트의 `accuracy_basis_points`를 그대로 표시한다. 1~4단계 지휘 명중 유효율은 각각 96%, 92%, 88%, 84%다. 이는 자원 소모 전에 실제 적용된 snapshot이며 명중·피해 결과를 구현한 것으로 표현하지 않는다.

## 검증

- G3-03R core: `PASS 60 / FAIL 0`
- G3-03R UI headless: `PASS 37 / FAIL 0`
- G3-03R UI GPU: `PASS 39 / FAIL 0`
- G3 편성 UI 회귀: `PASS 62 / FAIL 0`
- G4-01 전투 UI 회귀: `PASS 43 / FAIL 0`

최종 집중 회귀 13개 묶음은 G3·G4·G5·G6 연동을 포함해 총 `PASS 926 / FAIL 0`이다.

GPU 캡처: `out/demo-rc-g3-03r-command-penalty/command-penalty-1600x900.png` (1600×900), SHA-256 `8EF64F4038EBC5567BA336B854DFDB29CDCF12E088F868CDADA8BF728605E9F1`.

두 UI 파일은 순수 `Control` 기반 2D이며 `Node3D`, GLB, 3D 항해 화면 참조가 없다. 테스트는 공개 receipt 렌더링, 실제 battle viewer 경계, 적 수치 비공개, 실제·추정 사격 구분, 진형 변경 턴/유지 턴 문구를 검증한다.
