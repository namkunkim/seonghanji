class_name Domestic
extends RefCounted

## 내정 (region-power.md §3.5 · time-and-monetization.md §3.3)
##
## **모든 계산이 1/1000 단위 정수다.** 부동소수 금지 (dev-requirements.md §2.3).

## ---------------------------------------------------------------- 전화 회복
##
## §3.5-b 체감형:  C ← C + (0.95 − C) × r      단 C < 0.95 일 때만
##
## **정액 선형을 쓰지 않는 이유가 설계에 있다.** 매년 일정량을 더하면
## 익주(0.95)는 즉시 상한에 닿고 사예(0.25)는 백 년이 넘게 걸린다.
## 체감형은 잔여 피해량 `(0.95 − C)` 에 비례하므로
## `interludes.md` §2.3 의 「가장 많이 부서진 곳이 가장 많이 회복한다」를
## **산식 자체가 만족한다.**

## 회복 상한. 「전란이 없었다면 있었을 값」이며 완전 복원(1.0)은 없다 (§3.5-a)
const RECOVERY_CAP_MILLI: int = 950

## 기저 회복률 0.015
const RECOVERY_BASE_MILLI: int = 15

## 투자 단계당 0.005, 상한 0.020 (4단계)
const RECOVERY_PER_STAGE_MILLI: int = 5
const RECOVERY_MAX_STAGE: int = 4

## 회복은 1년에 한 번 정산한다
const RECOVERY_PERIOD_TICKS: int = GameClock.TICKS_PER_YEAR


## 그 권역의 연간 회복률(1/1000). 보정 셋을 반영한다 (§3.5-c).
static func recovery_rate_milli(st: RegionState, now_tick: int,
		wei_trait: bool = false) -> int:
	# 교전 중인 권역은 회복하지 않는다
	if st.contested:
		return 0
	var base := RECOVERY_BASE_MILLI
	# 위 세력 특성 — 「인구 회복 속도 +30%」가 기저에만 걸린다
	if wei_trait:
		base = base * 13 / 10
	var r := base + mini(st.recovery_investment, RECOVERY_MAX_STAGE) * RECOVERY_PER_STAGE_MILLI
	# 신복속 권역은 절반 (12개월간)
	if st.acquired_tick != RegionState.NEVER 			and now_tick - st.acquired_tick < GameClock.TICKS_PER_YEAR:
		r = r / 2
	return r


## 1년치 회복을 적용한다. 바뀐 양(1/1000)을 돌려준다.
static func apply_recovery(st: RegionState, now_tick: int,
		wei_trait: bool = false) -> int:
	if st.war_damage_milli >= RECOVERY_CAP_MILLI:
		return 0
	var r := recovery_rate_milli(st, now_tick, wei_trait)
	if r <= 0:
		return 0
	# **반올림한다.** 절사하면 55년 누적에서 문서값(§3.5-d)과 2~3% 어긋난다 —
	# 총 절대오차 161 대 48 로 반올림이 명확히 낫다 (2026-08-24 측정).
	# 부동소수를 쓸 수 없으므로(§2.3) 정수 반올림으로 오차를 줄인다.
	var gain := ((RECOVERY_CAP_MILLI - st.war_damage_milli) * r + 500) / 1000
	# 꼬리에서 이득이 0 이 되어 **영구히 멈추는 것을 막는다.**
	# 반올림해도 (950−C)×r < 500 이면 gain 이 0 이 되어 C=936 언저리에서 정지한다.
	# 그것은 설계가 아니라 정수 연산의 산물이다 — 0.95 는 상한이지 도달 불가점이 아니다.
	# 최소 1 로 두면 수렴이 보장되고, 꼬리 구간(연 0.001)은 55년 캠페인에서 무시할 만하다.
	gain = maxi(gain, 1)
	st.war_damage_milli = mini(st.war_damage_milli + gain, RECOVERY_CAP_MILLI)
	return gain


## n년 뒤의 전화 계수를 한 번에 낸다.  C_n = 0.95 − (0.95 − C_0) × (1 − r)^n
## 검산용이다. 실제 진행은 매년 apply_recovery 를 돈다.
static func recovery_after_years(c0_milli: int, r_milli: int, years: int) -> int:
	var c := c0_milli
	for _i in years:
		if c >= RECOVERY_CAP_MILLI:
			break
		var g := ((RECOVERY_CAP_MILLI - c) * r_milli + 500) / 1000
		c = mini(c + maxi(g, 1), RECOVERY_CAP_MILLI)
	return c


## ---------------------------------------------------------------- 명령 소요
##
## time-and-monetization.md §3.3 을 그대로 옮긴다. 소요표가 분 단위라 그대로 틱이다.

const DURATION := {
	"함대편성": 0,          # 즉시
	"성계외곽제압": 30,
	"식민지공략": 45,
	"함선생산": 60,         # 1전대
	"궤도권공략": 90,
	"개발": 120,            # 1단계 2~6시간. 하한을 쓴다
	"개발_최대": 360,
	"지구형행성공략": 240,
}


## 명령 소요(틱). 없는 명령이면 -1.
static func duration_ticks(kind: String) -> int:
	return DURATION.get(kind, -1)


## ---------------------------------------------------------------- 징병
##
## 인구가 징병 상한이자 세수 기반이다 (§1 국력 4요소).
## 신점령지·신복속 병력은 사기에 페널티가 붙는다 (§3.4-b 파생).

const MORALE_PENALTY_NEW_TERRITORY: int = -15
const MORALE_PENALTY_SURRENDERED: int = -25


## 징집 병력의 초기 사기 보정. 적벽에서 조조군 주력이
## **항복한 지 얼마 되지 않은 형주 수군**이었던 것이 이 값으로 설명된다.
static func levy_morale_penalty(st: RegionState, now_tick: int) -> int:
	if st.acquired_by == "항복" or st.acquired_by == "귀부":
		if st.is_newly_taken(now_tick):
			return MORALE_PENALTY_SURRENDERED
	if st.is_newly_taken(now_tick):
		return MORALE_PENALTY_NEW_TERRITORY
	return 0


## 그 권역에서 뽑을 수 있는 병력 상한. 인구에 전화 계수를 곱한다.
static func levy_cap(data: GameData, rid: String, st: RegionState) -> int:
	return data.region_power(rid) * st.war_damage_milli / 1000


## ================================================================ 명령 7종
##
## domestic.md §5. **삼국지 9 의 걸어두는 명령 + 13 의 담당관.**
## 플레이어는 시작할 때 한 번 누르고, 매달 누르지 않는다.
##
## 여섯은 권역·함대에 걸고 **기술만 세력에 건다** —
## 기술은 땅의 것이 아니라 나라의 것이므로 45 권역에 흩어지지 않는다.

const CMD_DEVELOP: String = "개발"
const CMD_RECOVER: String = "복구"
const CMD_CONSCRIPT: String = "징병"
const CMD_DRILL: String = "훈련"
const CMD_BUILD: String = "건조"
const CMD_TECH: String = "기술"
const CMD_DELEGATE: String = "위임"

## 명령 순서를 **고정한다** — 순회 순서가 결정론의 전제다 (§2.3)
const COMMANDS: Array[String] = [
	CMD_DEVELOP, CMD_RECOVER, CMD_CONSCRIPT, CMD_DRILL,
	CMD_BUILD, CMD_TECH, CMD_DELEGATE,
]

## ---------------------------------------------------------------- 비용

## 개발 — 인구 × 300 일시불 · 6개월 · 생산·수입 +10%p · 개발여지 1칸 소비
const DEVELOP_COST_PER_POP: int = 300
const DEVELOP_MONTHS: int = 6

## 복구 — 인구 × 20 / 월 · 단계당. **월정액이다**
const RECOVER_COST_PER_POP_STAGE: int = 20

## 징병 — 자금 50/점 · 상한 인구 × 0.5
const CONSCRIPT_COST_PER_POINT: int = 50
const CONSCRIPT_CAP_PCT: int = 50

## 훈련 — 전대당 20 / 월. **월정액이다**
const DRILL_COST_PER_SQUADRON: int = 20


## 개발 일시불 비용.
static func develop_cost(data: GameData, rid: String) -> int:
	return data.region_power(rid) * DEVELOP_COST_PER_POP


## 개발 소요(틱).
static func develop_ticks() -> int:
	return DEVELOP_MONTHS * GameClock.TICKS_PER_MONTH


## 권역 하나의 월 복구비.
##
## 조조가 사예 3권역(인구 38)을 전부 4단계로 올리면 월 3,040 —
## 잔여의 59% 다. **사예를 되살리는 것과 함대를 세우는 것이 같은 무게가 된다.**
static func recover_cost(data: GameData, rid: String, st: RegionState) -> int:
	return data.region_power(rid) * RECOVER_COST_PER_POP_STAGE \
		* mini(st.recovery_investment, RECOVERY_MAX_STAGE)


## 세력의 월 복구비 합. **정렬된 권역 배열로만 받는다.**
static func recover_cost_total(data: GameData, states: Dictionary,
		owned: Array) -> int:
	var sum := 0
	for rid in owned:
		var st: RegionState = states.get(rid)
		if st != null:
			sum += recover_cost(data, rid, st)
	return sum


## 징병 상한. 인구의 절반이다.
static func conscript_cap(data: GameData, rid: String) -> int:
	return data.region_power(rid) * CONSCRIPT_CAP_PCT / 100


## 함대 하나의 월 훈련비. 훈련이 걸려 있지 않으면 0.
static func drill_cost(fl: Fleet) -> int:
	if not fl.drilling or not fl.is_alive():
		return 0
	return fl.squadrons_milli() * DRILL_COST_PER_SQUADRON / 1000


## ---------------------------------------------------------------- 적용
##
## `Sim._deliver_commands` 는 도달한 명령을 옮기기만 했다. 여기서 **효과가 붙는다.**
##
## 돌려주는 것은 **사유 문자열**이다. 빈 문자열이면 성공 —
## 실패를 조용히 삼키면 「명령을 걸었는데 아무 일도 없다」가 된다.
static func apply(data: GameData, states: Dictionary, f: Faction,
		fleets: Array, cmd: Dictionary, now_tick: int) -> String:
	var kind := String(cmd.get("kind", ""))
	var p: Dictionary = cmd.get("payload", {})
	match kind:
		CMD_DEVELOP:
			return _apply_develop(data, states, f, String(p.get("region", "")))
		CMD_RECOVER:
			return _apply_recover(states, f, String(p.get("region", "")),
				int(p.get("stage", 0)))
		CMD_CONSCRIPT:
			return _apply_conscript(data, states, f, String(p.get("region", "")),
				int(p.get("amount", 0)))
		CMD_DRILL:
			return _apply_drill(fleets, f, int(p.get("fleet", -1)),
				bool(p.get("on", true)))
		CMD_TECH:
			return _apply_tech(f, String(p.get("axis", "")), now_tick)
		CMD_DELEGATE:
			return _apply_delegate(states, f, String(p.get("region", "")),
				bool(p.get("on", true)))
		_:
			return "알 수 없는 명령: " + kind


static func _owned(f: Faction, rid: String) -> bool:
	return f.regions.has(rid)


static func _apply_develop(data: GameData, states: Dictionary, f: Faction,
		rid: String) -> String:
	if not _owned(f, rid):
		return "보유 권역이 아니다"
	var st: RegionState = states.get(rid)
	if st == null:
		return "권역 없음"
	var slots := data.region_dev_slots(rid)
	if slots <= 0:
		return "개발 대상이 아니다"          # 태양계권 — 복구도로 판정한다
	if st.development >= slots:
		return "개발여지 소진"
	var cost := develop_cost(data, rid)
	if f.treasury < cost:
		return "자금 부족"
	f.treasury -= cost
	st.development += 1
	return ""


static func _apply_recover(states: Dictionary, f: Faction, rid: String,
		stage: int) -> String:
	if not _owned(f, rid):
		return "보유 권역이 아니다"
	var st: RegionState = states.get(rid)
	if st == null:
		return "권역 없음"
	st.recovery_investment = clampi(stage, 0, RECOVERY_MAX_STAGE)
	return ""                                  # 비용은 월 정산에서 걷는다


static func _apply_conscript(data: GameData, states: Dictionary, f: Faction,
		rid: String, amount: int) -> String:
	if not _owned(f, rid):
		return "보유 권역이 아니다"
	var st: RegionState = states.get(rid)
	if st == null or amount <= 0:
		return "권역 없음"
	var room := conscript_cap(data, rid) - st.garrison
	if room <= 0:
		return "징병 상한"
	var n := mini(amount, room)
	var cost := n * CONSCRIPT_COST_PER_POINT
	if f.treasury < cost:
		n = f.treasury / CONSCRIPT_COST_PER_POINT
		if n <= 0:
			return "자금 부족"
		cost = n * CONSCRIPT_COST_PER_POINT
	f.treasury -= cost
	st.garrison += n
	return ""


static func _apply_drill(fleets: Array, f: Faction, fleet_id: int,
		on: bool) -> String:
	for fl in fleets:
		if fl.id == fleet_id:
			if fl.owner != f.id:
				return "자기 함대가 아니다"
			fl.drilling = on
			return ""
	return "함대 없음"


static func _apply_tech(f: Faction, axis: String, now_tick: int) -> String:
	if not Tech.AXES.has(axis):
		return "알 수 없는 축: " + axis
	if not f.tech_research.is_empty():
		return "이미 개발 중"                   # 한 번에 한 축만
	var lv := int(f.tech.get(axis, 0))
	var cost := Tech.cost(lv)
	if cost < 0:
		return "최대 단계"
	if f.treasury < cost:
		return "자금 부족"
	f.treasury -= cost
	f.tech_research = {
		"axis": axis,
		"done_tick": now_tick + Tech.ticks(lv, f.tech_fast),
	}
	return ""


static func _apply_delegate(states: Dictionary, f: Faction, rid: String,
		on: bool) -> String:
	if not _owned(f, rid):
		return "보유 권역이 아니다"
	var st: RegionState = states.get(rid)
	if st == null:
		return "권역 없음"
	st.delegated = on
	return ""


## 진행 중인 기술이 완성되었는가. 완성했으면 축 이름을 돌려준다.
static func tech_tick(f: Faction, now_tick: int) -> String:
	if f.tech_research.is_empty():
		return ""
	if now_tick < int(f.tech_research.get("done_tick", 0)):
		return ""
	var axis := String(f.tech_research["axis"])
	f.tech[axis] = int(f.tech.get(axis, 0)) + 1
	f.tech_research = {}
	return axis


## 훈련 1개월분. 상한은 **전대장 통솔**이며 없으면 40 에서 멈춘다.
static func drill_tick(fl: Fleet) -> void:
	if not fl.drilling or not fl.is_alive():
		return
	fl.drill = mini(fl.drill + Battle.DRILL_GAIN_PER_MONTH, fl.drill_cap())
