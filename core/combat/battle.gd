class_name Battle
extends RefCounted

## 전투 해결 (combat.md §1 · §3 · §4)
##
## **이 게임의 전투는 전멸이 아니라 패주로 끝난다** (§1).
## 사기가 전투력을 조금 깎고 **붕괴 판정을 크게 당긴다.**
##
## 모든 계수를 **1/1000 단위 정수**로 다룬다 — 부동소수 금지 (§2.3).

## ---------------------------------------------------------------- 절대 스케일
## combat.md §4.3.1 — 지수 1 = 자금 100 = 유지점 1 · 전대 40척 · 함대 200척
const SQUADRON_SHIPS: int = 40
const FLEET_SHIPS: int = 200

## 페이즈
enum Phase { CONTACT, BARRAGE, ENGAGEMENT, ASSAULT, RESOLUTION }

const PHASE_NAMES: Array[String] = ["접적", "포화", "교전", "강습", "결착"]

## 지휘관 보정 폭 (§3.2). 1/1000.
## **통솔이 가장 넓다** — 함대전의 중심 스탯이기 때문이다.
const COMMANDER_RANGE_MILLI: Array[int] = [400, 300, 500, 500, 350]

## 페이즈별 적용 스탯 (§3.2)
const PHASE_STAT: Array[String] = ["지력", "지력", "통솔", "무력", "통솔"]


## ---------------------------------------------------------------- 지휘관 보정
##
## 스탯 50 이 중립(×1.0)이고, 100 이면 상한, 0 이면 하한이다.
##     보정 = 1 + (스탯 − 50) / 50 × 폭
static func commander_modifier_milli(stat: int, phase: int) -> int:
	var range_milli: int = COMMANDER_RANGE_MILLI[phase]
	return 1000 + (stat - 50) * range_milli / 50


## ---------------------------------------------------------------- 사기
##
## §3.4  사기 계수 = 0.6 + 사기 / 250
##
## **폭을 좁게 잡았다 (0.68~1.10).** 사기가 전투력을 직접 좌우하면
## 한 번 밀린 쪽이 가속도로 무너져 5페이즈 구조가 의미를 잃는다.
const MORALE_NOMINAL: int = 100
const MORALE_MAX: int = 125
const MORALE_COLLAPSE_FLOOR: int = 19     # 19 이하는 판정 없이 즉시 붕괴
const MORALE_COLLAPSE_CEIL: int = 39      # 39~20 구간에서 매 페이즈 굴린다


static func morale_coefficient_milli(morale: int) -> int:
	return 600 + morale * 1000 / 250


## §1.4  붕괴 확률(%) = (40 − 사기) × 3 − (통솔 − 50)/50 × 15      [0 ~ 90]
##
## **통솔이 붕괴를 늦춘다. 다만 막지는 못한다** —
## 사기 30 이하에서 특급 지휘관도 여섯 번에 한 번은 무너진다.
## 지휘관이 좋다는 것은 무적이라는 뜻이 아니라 **시간을 번다**는 뜻이다.
static func collapse_chance_pct(morale: int, command: int) -> int:
	if morale <= MORALE_COLLAPSE_FLOOR:
		return 100
	if morale > MORALE_COLLAPSE_CEIL:
		return 0
	var base := (40 - morale) * 300              # 1/100 단위로 계산
	var bonus := (command - 50) * 1500 / 50
	return clampi((base - bonus) / 100, 0, 90)


## ---------------------------------------------------------------- 지형
##
## §4.2 · star-map.md §3.3 규칙 ②③

## 회랑 내 동시 전개 함대 수 상한 (star-map.md §3.3 ②)
## 대회랑 1~2 · 중회랑 2~3. **하한을 기본값으로 쓴다** —
## 「검각에서는 전대 다섯 몫(=1 함대)만 싸운다」(§3.3)가 대회랑 1 을 지목한다.
static func corridor_fleet_cap(scale: String) -> int:
	match scale:
		"대회랑": return 1
		"중회랑": return 2
	return 0                                      # 회랑이 아니면 제한 없음


## 회랑에서 실제로 싸우는 함선 수. **이것이 「일부당관」의 실체다.**
## 검각에서는 2,000척과 200척의 차이가 사실상 사라진다 —
## 국가의 총력을 회랑 하나에 밀어 넣어도 전대 다섯 몫만 싸운다.
static func deployable_ships(ships: int, corridor_scale: String) -> int:
	var cap := corridor_fleet_cap(corridor_scale)
	if cap <= 0:
		return ships
	return mini(ships, cap * FLEET_SHIPS)


## 회랑 함종 보정 (§4.2 · §3.3 ③). 1/1000.
static func terrain_ship_modifier_milli(ship_type: String, corridor: bool) -> int:
	if not corridor:
		return 1000
	match ship_type:
		"포격함": return 1600            # +60%
		"강습모함": return 600           # −40%
	return 1000


## ---------------------------------------------------------------- 전투력
##
## §3.1  부대 전투력 = 함선 수 × 함종 계수(페이즈) × 지휘관 보정
##                    × 지형 보정 × 특성 보정 × 사기 계수
static func combat_power_milli(ships: int, ship_phase_coeff_milli: int,
		commander_stat: int, phase: int, morale: int,
		terrain_milli: int = 1000, trait_milli: int = 1000,
		corridor_scale: String = "") -> int:
	var n := deployable_ships(ships, corridor_scale)
	var v := n * ship_phase_coeff_milli
	v = v * commander_modifier_milli(commander_stat, phase) / 1000
	v = v * terrain_milli / 1000
	v = v * trait_milli / 1000
	v = v * morale_coefficient_milli(morale) / 1000
	return v


## ---------------------------------------------------------------- 전력비
##
## §3.3  1.5배 유리 · 3배 압도적 · 5배 이상 추가 이득 급감
##
## ⚠ **문서가 곡선을 주지 않았다.** 구간 이름만 있다.
## 지금은 구간 판정만 하고, 실제 감쇠 곡선은 M0 밸런스 검증에서 정한다.
static func advantage_tier(power_a: int, power_b: int) -> String:
	if power_b <= 0:
		return "일방"
	var ratio_milli := power_a * 1000 / power_b
	if ratio_milli >= 5000:
		return "포화"          # 추가 이득 급감
	if ratio_milli >= 3000:
		return "압도"
	if ratio_milli >= 1500:
		return "우세"
	if ratio_milli >= 667:
		return "호각"
	return "열세"


## ---------------------------------------------------------------- 페이즈별 사기 증감
##
## §1.3  Δ사기 = − [ L × k(페이즈) + D + E ]

## k — 페이즈 계수. ③ 교전이 최대인 것은 「진형 격돌 · 사기 소모 최대」를 옮긴 것이다.
## 같은 1% 손실이 교전에서는 접적의 2.5배로 아프다.
const MORALE_K_MILLI: Array[int] = [800, 1200, 2000, 1600, 1000]

## 기본 손실률(%). 1/1000 단위 — 1.0% = 1000
const BASE_LOSS_MILLI: Array[int] = [1000, 4000, 7000, 5000, 3000]

## D 상한 (§1.3)
const PRESSURE_MAX_MILLI: int = 15000


## L — 손실률(%). 1/1000 단위.
##
##     L = 기본 손실률(페이즈) × √(적 실효 전력 / 아군 실효 전력)
##
## 제곱근을 쓰는 이유는 §3.3 체감 곡선과 같다 —
## **전력비 4배라도 손실은 2배로만 늘어난다.**
static func loss_rate_milli(phase: int, own_power: int, foe_power: int) -> int:
	if own_power <= 0:
		return 100000
	var ratio_milli := foe_power * 1000 / own_power
	return BASE_LOSS_MILLI[phase] * FixedMath.sqrt_milli(ratio_milli) / 1000


## D — 열세 압박. 1/1000 단위. 우세측은 0.
##
##     D = 6 × log₂(적 실효 전력 / 아군 실효 전력)      [0 ~ 15]
##
## **D 는 총 전력이 아니라 전개 전력으로 계산한다.**
## 회랑에는 동시 전개 상한이 있으므로 전력비 자체가 커질 수 없고 D 도 오르지 않는다 —
## **검각에서는 2,000척이 200척을 압박하지 못한다. 숫자가 보이지 않기 때문이다.**
static func pressure_milli(own_power: int, foe_power: int) -> int:
	if own_power <= 0:
		return PRESSURE_MAX_MILLI
	if foe_power <= own_power:
		return 0
	var ratio_milli := foe_power * 1000 / own_power
	var d := 6 * FixedMath.log2_milli(ratio_milli)
	return clampi(d, 0, PRESSURE_MAX_MILLI)


## 한 페이즈의 사기 증감. 정수(사기 단위)로 돌려준다. 음수다.
static func morale_delta(phase: int, own_power: int, foe_power: int,
		event_milli: int = 0) -> int:
	var l := loss_rate_milli(phase, own_power, foe_power)
	var k: int = MORALE_K_MILLI[phase]
	var d := pressure_milli(own_power, foe_power)
	var total: int = l * k / 1000 + d + event_milli
	return -(total / 1000)
