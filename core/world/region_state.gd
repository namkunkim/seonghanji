class_name RegionState
extends RefCounted

## 권역의 가변 상태 (region-power.md §3)
##
## 불변 제원(인구·생산·수입·방어)은 `data/regions.json` 에 있다.
## 여기 담는 것은 **플레이 중에 변하는 것**뿐이다.
##
## 모든 비율을 **1/1000 단위 정수**로 다룬다 — 부동소수 금지 (dev-requirements.md §2.3).

## 전화 계수. 0.25 ~ 0.95 를 250 ~ 950 으로 담는다 (§3.1)
var war_damage_milli: int = 950

## 소유 세력. 빈 문자열이면 중립
var owner: String = ""

## 획득 이력 없음을 뜻하는 센티넬.
## **음수를 「없음」으로 쓰면 시나리오 시작 전 획득을 표현할 수 없다** —
## 조조의 유주·병주는 207년(시작 1년 전) 정복이다 (§3.4-c). 2026-08-25 수정.
const NEVER: int = -999_999

## 획득 시각(틱). 신복속 판정에 쓴다 — 획득 후 게임 내 3년 이내 (§3.4-b ②)
## 시작 전 획득은 음수로 적는다. 예) -720 = 1년 전
var acquired_tick: int = NEVER

## 획득 방식. 동원율의 신복속 부담 계수가 여기서 갈린다 (§3.4-b ②)
##   무력 정복 ×1.0 · 항복·귀부 ×0.6 · 협정 이양 ×0.3
var acquired_by: String = ""

## 교전 중인가. 전선인 동안에는 회복하지 않는다 — 폐허가 되는 중이다 (§3.5-c)
var contested: bool = false

## 복구 투자 단계 0~4. r_투자 = 단계 × 0.005 (§3.5-b, 상한 0.020)
var recovery_investment: int = 0

## 개발 단계. 개발여지를 소비해 생산을 올린다
var development: int = 0

## 주둔 병력 (실동원 단위)
var garrison: int = 0


func is_newly_taken(now_tick: int) -> bool:
	if acquired_tick == NEVER:
		return false
	return now_tick - acquired_tick < GameClock.TICKS_PER_YEAR * 3
