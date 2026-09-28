# DEMO-RC-G6-06 — 보급함 재고·손상 처리량·거점 재적재

## 수용 범위

G6-06은 SHP-05 보급함 전대 단위의 제한 재고와 피해 상태에 따른 처리량, 아군 거점 정박 재적재를 G6-03 자동 보급 pipeline에 연결한다. normal-demo 최대 재고는 연료 `10000bp`, 탄약 `12`, 보급 자재 `4`이고 초기 재고도 최대치다. 재고는 함선별로 중복 생성하지 않으며 provider squadron/source가 단일 권위다.

정상·중파·대파 처리율은 각각 `10000/5000/2500bp`이고 정상 기준 처리량은 전대당 한 턴 `1`이다. 다음 턴으로 이월되는 값은 `10000bp` 미만의 소수 잔여뿐이다. 이번 턴에 사용하지 않은 정수 슬롯은 축적되지 않는다. T1에도 credit을 준비하고 `continue_turn()`은 다음 턴 credit을 준비하며, 같은 턴의 supply resolve 재진입은 중복 credit을 만들지 않는다.

보급은 완전 충전만 허용하는 원자 처리다. 연료는 실제 지급량, 탄약은 G4 finite ammo/special 실제 지급량, 보급 자재는 완료 전대당 1을 차감한다. 우선 후보의 재고가 부족하면 `waiting_inventory`로 남기고 재고를 부분 차감하지 않으며, 뒤의 결정론적 후보가 충족 가능하면 계속 처리한다.

## 피해·파괴·나포 경계

중파와 대파는 재고를 보존하면서 처리율만 낮춘다. 기존 생존 `N`척 중 `d`척이 파괴되면 현재 재고와 최대 재고를 모두 `floor(before × (N-d) / N)`으로 줄여 이후 거점 재적재가 파괴된 함선 몫을 되살리지 못하게 한다. 나포는 남은 재고를 전부 폐기하고 포획자 획득량은 0으로 고정하며 source를 즉시 비활성화한다. recovery와 inventory 상태는 같은 판정에서 원자 커밋된다.

정상 보급함의 근접은 damage나 capture를 만들지 않는다. G6-06의 내부 상태·나포 fixture는 `authority=G8-00`인 권위 intent만 명령/판정 전 단계(`liu_command`, `sun_control_prompt`, `sun_command`, `resolution`)에서 수용한다. 판정 완료 뒤 `victory_check`와 `turn_limit`에서는 거부하고 상태 digest를 바꾸지 않는다. 실제 damage/destroy/boarding 발생 조건과 전투 효과는 **DEMO-RC-G8-00**의 권위다.

## 거점 재적재

보급함은 같은 세력의 우호 거점에서만 실제 이동거리 0으로 한 턴 연속 정박한 뒤 최대 재고까지 재적재한다. 연합 거점, 강습모함, 이동식 source, 보급함 사이 전송은 허용하지 않는다. 재적재는 해당 턴의 outbound 고속정 보급 뒤 실행되므로 채운 재고는 다음 턴부터 사용할 수 있다.

## Viewer와 UI

viewer는 관전자 세력 소유의 정확한 provider만 공개한다. 적 보급함의 정확한 재고 행과 관련 이벤트는 제거한다. 읽기 전용 UI는 연료·탄약·보급 자재, 함선 상태 수, 거점 정박/재적재 상태, 비활성 사유와 함께 `effective_throughput_basis_points_per_turn`, `available_capacity_squadrons_this_turn`, `base_capacity_squadrons_per_turn`을 분리해 표시한다. 문구는 `처리율 N bp/턴 · 이번 턴 잔여 N전대 · 정상 기준 N전대/턴`이며 상태를 바꾸는 버튼은 없다. 화면은 기존 `Control` 기반 2D 전용이고 3D 자산을 읽거나 수정하지 않는다.

상태 snapshot은 JSON primitive 왕복 뒤 같은 inventory/recovery 결과를 재현한다. 전체 전투 저장·불러오기 UX와 장기 호환성은 G8-06/G8-07 범위이며 여기서 완료로 주장하지 않는다.

## 구현 중 선행 조건 교정

clean 기준선의 `data/red-cliffs-sensor-ew-rules.json`에는 이미 활성인 G5-03 지형 효과가 `pending_neutral`로 남아 현재 validator와 충돌했다. 실제 G5-03 계약에 맞춰 해당 terrain 상태 한 줄을 `active_normal_demo`로 교정했고, 그 외 sensor/EW 수치는 바꾸지 않았다.

## 검증 영수증

- G6-06 core: `68/68`, UI headless: `26/26`
- G6-06 Windows GPU: `28/28`, Intel Arc 130V, `1600×900`
- G6-01~G6-06 관련 core/UI 회귀: `822/822`
- 전체 코어: `35/35` sections, `701/701` assertions
- 독립 QA: 최초 P1/P2 지적을 교정한 뒤 잔여 `P1 0 / P2 0`
- 캡처: `out/demo-rc-g6-06-supply-inventory/supply-inventory-1600x900.png`
- 캡처 SHA-256: `349430A05134E2CCD696F2A4F9EBBAD7A81DF37BC2E6BEE456796C09E0CEDCAA`

`out/`은 커밋하지 않는다. G6-06을 수용하며 다음 작업은 **DEMO-RC-G8-00 — 전투 피해·사기·센서·지형 효과 적용**이다.
