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
