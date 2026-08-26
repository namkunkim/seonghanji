class_name Economy
extends RefCounted

## 경제 — 자금 · 행정비 · 함대 유지비 (domestic.md §4 · combat.md §4.3)
##
## **자원은 셋이다.**
##   자금    유량. 매월 들어오고 매월 나간다
##   유지점  상한. 실동원이 그대로 상한이다
##   행정비  **가진 것에 붙는 비용.** V-33 에서 신설했다
##
## 모든 계산이 정수다 — 부동소수 금지 (dev-requirements.md §2.3).
## 자금은 **1/1000 단위(밀리)**로 다루다 세력 단위에서 한 번만 내린다.

## ---------------------------------------------------------------- 눈금
##
## `combat.md` §4.3.1 이 못 박은 것:
##   국력 지수 1 = 기간당 자금 100 = 유지점 1
##
## **「기간」을 게임 내 1개월로 확정한다** (domestic.md §4.0).
## 건조 소요가 시간 단위이고 실플레이 1시간 = 게임 내 1개월이므로,
## 전열함 한 전대를 한 달에 짓고 그 비용이 국력 1 의 한 달 수입과 같다.
const INCOME_PER_INDEX: int = 100
const SETTLE_PERIOD_TICKS: int = GameClock.TICKS_PER_MONTH


## ---------------------------------------------------------------- 행정 계수
##
## **통치 체제에 연동한다.** 새 눈금을 만들지 않았다 —
## 정본이 이미 동원율에 매겨 둔 다섯 체제에 계수를 붙였을 뿐이다
## (region-power.md §3.4-b ④ · JOBS.md §4 검토 5).
##
## **더 걷는 체제가 더 쓴다.** 중앙집권은 병력을 더 뽑지만 관료를 더 먹인다.
const ADMIN_COEF := {
	"중앙집권": 30,
	"표준": 24,
	"호족연합": 18,
	"군벌연합": 12,
	"암약": 8,
}
const ADMIN_COEF_DEFAULT: int = 24


static func admin_coef(governance: String) -> int:
	return int(ADMIN_COEF.get(governance, ADMIN_COEF_DEFAULT))


## ---------------------------------------------------------------- 위임
##
## 직할 대 위임 (domestic.md §3). **실동원 −50% 가 대가의 본체다** —
## 위임한 땅의 병력을 중앙이 쓰지 못한다. 정확히 후한 말의 주목이 그랬다.
const DELEGATED_INCOME_PCT: int = 70
const DELEGATED_ADMIN_PCT: int = 30
const DELEGATED_MOBILIZATION_PCT: int = 50


## ---------------------------------------------------------------- 개발
##
## 개발 한 단계 = 생산·수입 +10%p (기저 대비 정액. 복리가 아니다)
const DEVELOPMENT_STEP_PCT: int = 10


## 권역 하나의 월 수입 (**1/1000 자금**).
##
## **수입은 「수입」 열에서 나온다. 인구 열이 아니다** (domestic.md §4.1) —
## §4.3.1 의 「국력 지수 1 = 자금 100」은 스케일 앵커이고,
## 권역별 실제 값은 region-power.md §2 의 수입 열이 정본이다.
##
## 나눗셈이 정확히 떨어진다. (1000 + 100×개발) 이 항상 100 의 배수이므로
## 곱은 100 의 배수이고 10 으로 나누어도 나머지가 없다 — **절사 오차가 없다.**
static func region_income_milli(data: GameData, rid: String, st: RegionState) -> int:
	var base := data.region_income(rid)
	if base <= 0:
		return 0
	# **×10 이다. ×100 이 아니다** — 1000 이 100% 이므로 10%p 는 100 이다.
	# 2026-08-25: 처음에 ×100 으로 적어 개발 한 단계가 +10%p 가 아니라
	# **+100%** 가 되어 있었다. 시험이 잡았다.
	var dev_factor := 1000 + DEVELOPMENT_STEP_PCT * 10 * st.development
	var v := base * dev_factor * st.war_damage_milli / 10
	if st.delegated:
		v = v * DELEGATED_INCOME_PCT / 100
	return v


## 권역 하나의 월 행정비 (**1/1000 자금**).
##
## > **전화 계수가 걸리지 않는다.**
## > 수입은 전란으로 죽지만 통치 비용은 죽지 않는다 —
## > 사예는 수입이 4분의 1로 줄었으나 **사람은 여전히 거기 산다.**
static func region_admin_milli(data: GameData, rid: String, st: RegionState,
		coef: int) -> int:
	var v := data.region_power(rid) * coef * 1000
	if st.delegated:
		v = v * DELEGATED_ADMIN_PCT / 100
	return v


## 세력의 월 수입(자금). **정렬된 권역 배열로만 받는다** — 순회 순서가 결정론의 전제다.
static func faction_income(data: GameData, states: Dictionary,
		owned: Array) -> int:
	var sum := 0
	for rid in owned:
		var st: RegionState = states.get(rid)
		if st != null:
			sum += region_income_milli(data, rid, st)
	return _to_gold(sum)


## 세력의 월 행정비(자금).
static func faction_admin(data: GameData, states: Dictionary,
		owned: Array, governance: String) -> int:
	var coef := admin_coef(governance)
	var sum := 0
	for rid in owned:
		var st: RegionState = states.get(rid)
		if st != null:
			sum += region_admin_milli(data, rid, st, coef)
	return _to_gold(sum)


## 밀리 → 자금. **반올림한다.** 절사하면 45 권역에서 매달 오차가 누적된다
## (domestic.gd 의 전화 회복에서 같은 판단을 이미 했다).
static func _to_gold(milli: int) -> int:
	return (milli + 500) / 1000 if milli >= 0 else -((-milli + 500) / 1000)


## ---------------------------------------------------------------- 편성
##
## 함종 순서를 **고정한다.** 순회 순서가 결정론의 전제다 (§2.3).
const SHIP_KINDS: Array[String] = ["전열", "포격", "강습", "전자", "공성", "보급"]

## 함종별 유지점 (1/1000). combat.md §4.3.2
const SHIP_POINT_MILLI := {
	"전열": 1000, "포격": 1400, "강습": 1600,
	"전자": 1400, "공성": 1500, "보급": 600,
}

## 함종별 자금 유지비 (전대당). 건조 비용의 10% — **공성함만 6%**다.
## 「평시엔 놀린다」 (combat.md §4.3.2)
const SHIP_UPKEEP := {
	"전열": 10, "포격": 14, "강습": 18,
	"전자": 15, "공성": 12, "보급": 6,
}

## 편성안 6종. 순서는 SHIP_KINDS 와 같다 (ship-specs.md §7.2)
##
## **2026-08-25 정정.** 문서의 전대당 유지점 표에서 균형(1.175)과
## 개활 결전(1.200)이 함종 값과 맞지 않았다 — 여섯 중 넷은 정확하고
## 둘만 0.020 씩 반대 방향으로 어긋나 있었다. 여기서는 **비율에서 계산한다.**
## 값을 두 곳에 적지 않으면 두 곳이 어긋날 일도 없다 (V-35).
const PLANS := {
	"균형":      [40, 20, 15, 10,  5, 10],
	"회랑 돌파": [30, 40,  5,  5, 10, 10],
	"개활 결전": [45, 15, 20, 10,  0, 10],
	"강습 특화": [30, 10, 35, 10,  0, 15],
	"성계 공략": [30, 15, 15,  5, 25, 10],
	"봉쇄 유지": [45, 25,  0, 15,  0, 15],
}
const PLAN_DEFAULT: String = "균형"


## 편성안의 전대당 유지점 (1/1000). 균형 = 1195.
static func plan_point_milli(plan: String) -> int:
	var r: Array = PLANS.get(plan, PLANS[PLAN_DEFAULT])
	var sum := 0
	for i in SHIP_KINDS.size():
		sum += int(r[i]) * int(SHIP_POINT_MILLI[SHIP_KINDS[i]])
	return sum / 100


## 편성안의 전대당 자금 유지비 (1/1000). 균형 = 12200.
static func plan_upkeep_milli(plan: String) -> int:
	var r: Array = PLANS.get(plan, PLANS[PLAN_DEFAULT])
	var sum := 0
	for i in SHIP_KINDS.size():
		sum += int(r[i]) * int(SHIP_UPKEEP[SHIP_KINDS[i]]) * 1000
	return sum / 100


## 실동원을 전대 수로 환산한다 (1/1000 전대).
## **실동원이 곧 함대 상한이다** — 자금이 남아도 이것을 넘지 못한다.
static func squadrons_milli(mobilized: int, plan: String = PLAN_DEFAULT) -> int:
	var pt := plan_point_milli(plan)
	if pt <= 0:
		return 0
	return mobilized * 1000 * 1000 / pt


## 주둔 상태별 유지비 배율(%). combat.md §4.3.2
##
## > **회랑 봉쇄 유지비 ×1.5 가 여기서 나온다.**
## > 검각을 막는 것은 공짜가 아니다 — **막고 있는 동안 계속 돈이 나간다.**
const STATION_MULT := {
	"자국": 100, "회랑": 150, "원정": 130, "비지": 200,
}


## 함대 유지비(자금). 전대 수는 1/1000 단위로 받는다.
static func fleet_upkeep(squadrons_m: int, plan: String = PLAN_DEFAULT,
		station: String = "자국") -> int:
	var per := plan_upkeep_milli(plan)
	var mult := int(STATION_MULT.get(station, 100))
	return _to_gold(squadrons_m * per / 1000 * mult / 100)


## 세력의 월 수지. [수입, 행정비, 함대비, 잔여]
##
## **조조만 잔여가 28% 다** (domestic.md §4.4). 크기 때문이 아니라
## 전화가 심한 땅을 많이 가졌기 때문이다 — 그가 이긴 곳들이 그가 부순 곳들이다.
static func balance(data: GameData, states: Dictionary, owned: Array,
		governance: String, squadrons_m: int,
		plan: String = PLAN_DEFAULT, station: String = "자국") -> Array:
	var inc := faction_income(data, states, owned)
	var adm := faction_admin(data, states, owned, governance)
	var flt := fleet_upkeep(squadrons_m, plan, station)
	return [inc, adm, flt, inc - adm - flt]
