class_name Fleet
extends RefCounted

## 함대 (combat.md §4.3.1 — 전대 40척 · 함대 200척)

var id: int = 0
var owner: String = ""

## 현재 성계. 이동 중이면 출발지
var at_system: String = ""

## 목적 권역. 없으면 주둔
var target_region: String = ""

## 도착 틱. -1 이면 이동 중이 아니다
var arrival_tick: int = -1

var ships: int = Battle.FLEET_SHIPS
var morale: int = Battle.MORALE_NOMINAL

## 편성안 (ship-specs.md §7.2). 전대당 유지점·유지비가 여기서 갈린다
var plan: String = Economy.PLAN_DEFAULT

## 주둔 상태. 유지비 배율이 갈린다 — **회랑 봉쇄는 ×1.5** (combat.md §4.3.2)
var station: String = "자국"

## ---------------------------------------------------------------- 지휘부
##
## **임명 4계층** (ship-specs.md §6.4). 필수는 제독뿐이고
## 빈 자리는 무명 장교가 맡아 보정 0 이다 — 임명은 의무가 아니라 자원 배분이다.

## 제독 스탯 (없으면 평균 50 = 보정 없음)
var command: int = 50
var might: int = 50
var wits: int = 50

## 부제독 통솔. **절반이 제독의 지휘 한도에 가산된다** (§6.5).
## `ship-specs.md` 검토 4(「초과 사기 −30 이 과도한가」)를 페널티를 낮추지 않고 푼다
var vice_command: int = 0

## 임무대장 — 강습(무력) · 공성(지력) · 보급(정치).
## **보급대장에서 정치가 처음으로 전장에 들어온다** (§6.5)
var assault_might: int = 0
var siege_wits: int = 0
var supply_politics: int = 0

## ---------------------------------------------------------------- 전대
##
## **전대가 최소 임무 단위다** (§6.4). 전대 하나로 출격·교전·훈련이 성립한다.

## 훈련도 0~100. 징병 직후 20 · 훈련 +8/월 · 상한은 **전대장 통솔**
## (domestic.md §5.5). 붕괴 판정에만 걸린다 — 이기게 하지 않고 버티게 한다
var drill: int = Battle.DRILL_NOMINAL

## 전대장 통솔. 0 이면 무명 장교이고 훈련 상한이 40 에서 멈춘다
var squadron_command: int = 0

## 훈련 명령이 걸려 있는가. **지속형이다** — 해제할 때까지 매월 비용이 나간다
var drilling: bool = false


## 이 함대의 전대 수 (1/1000 단위). 함선 200척 = 5전대
func squadrons_milli() -> int:
	return ships * 1000 / Battle.SQUADRON_SHIPS


## 훈련도 상한. 전대장이 없으면 40 이다 —
## **붙이지 않으면 그 전대는 영원히 숙련 이하다**
func drill_cap() -> int:
	return maxi(squadron_command, Battle.DRILL_CAP_UNLED)


func is_moving() -> bool:
	return arrival_tick >= 0


func is_alive() -> bool:
	return ships > 0
