class_name Diplomacy
extends RefCounted

## 외교 (diplomacy.md §4.5 · §5 · ai-design.md §8)
##
## ## 중원 세력 간 동맹
##
## `diplomacy.md` §4.5 가 이 공백을 지목했다 —
## > 본 문서 §1~4 는 「외국 세력」과의 동맹만 다뤘다.
## > **손유 동맹 같은 중원 세력 간 동맹 시스템이 비어 있었다.**
##
## §5 의 4단계를 중원 세력 간에도 그대로 쓰되 **천명 감소는 없다.**
## 같은 한의 신하끼리 손잡는 것이기 때문이다.
##
## ## 동맹 신뢰도는 계승된다
##
## > **208년의 신뢰도가 219년 형주 문제로 계승된다.**
## > 「동맹은 승리하는 순간부터 깨지기 시작한다.」

## §5 4단계
enum Tier { NONE, 통교, 화친, 맹약, 군사동맹 }

const TIER_NAMES := ["없음", "통교", "화친", "맹약", "군사동맹"]

## 동맹 신뢰도. 1/1000. 시작은 중립 500
## ---------------------------------------------------------------- 신뢰도 구간
##
## function-events.md §0.3-③ 은 0~100 눈금으로 적었고 여기는 0~1000 이다.
## **눈금을 새로 만들지 않고 환산한다** — 값을 두 곳에 두면 두 곳이 어긋난다.
##
##   70~100 고   배후 기습 미발동 · 동맹 유지 루트 개방
##   40~69  중   반환 요구 → 협상 또는 결렬
##   0~39   저   **[F-12] 배후 기습 판정 개시**
const TRUST_BAND_HIGH: int = 700
const TRUST_BAND_MID: int = 400

const TRUST_INITIAL: int = 500
const TRUST_MAX: int = 1000

## 공동 전투 시 상승 · 참전 거부 시 급락 (§5.1)
const TRUST_JOINT_BATTLE: int = 60
const TRUST_REFUSE_CALL: int = -250

## ai-design.md §8.1 위협도 구간
const THREAT_COALITION_MILLI: int = 2000   # 2.0 초과 → 견제 연합 결성 시도 (F-07)
const THREAT_SURRENDER_MILLI: int = 4000   # 4.0 초과 → 항복 검토 (F-26)

## 인접도 보정 — 접한 세력은 더 위협적이다
const THREAT_ADJACENT_MILLI: int = 500

var tiers: Dictionary = {}      # "A|B" → Tier
var trust: Dictionary = {}      # "A|B" → 1/1000


static func trust_band(trust: int) -> String:
	if trust >= TRUST_BAND_HIGH:
		return "고"
	if trust >= TRUST_BAND_MID:
		return "중"
	return "저"


## **[F-12] 배후 기습 판정이 열리는가.**
## 신뢰도가 「저」로 떨어진 동맹은 등 뒤가 위험해진다.
func backstab_open(a: String, b: String) -> bool:
	return is_allied(a, b) and trust_of(a, b) < TRUST_BAND_MID


## 배신 기록. **신뢰도와 별개로 횟수를 영구 계승한다** (§0.3-③) —
## [F-14] 복원 상한을 깎는다
var betrayals: Dictionary = {}


func record_betrayal(a: String, b: String) -> void:
	var k := key(a, b)
	betrayals[k] = int(betrayals.get(k, 0)) + 1


func betrayal_count(a: String, b: String) -> int:
	return int(betrayals.get(key(a, b), 0))


static func key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)


func tier_of(a: String, b: String) -> int:
	return int(tiers.get(key(a, b), Tier.NONE))


func trust_of(a: String, b: String) -> int:
	return int(trust.get(key(a, b), TRUST_INITIAL))


func is_allied(a: String, b: String) -> bool:
	return tier_of(a, b) >= Tier.맹약


## 군사동맹만 참전 의무가 있다 (§5.1)
func has_duty(a: String, b: String) -> bool:
	return tier_of(a, b) >= Tier.군사동맹


func set_tier(a: String, b: String, t: int) -> void:
	tiers[key(a, b)] = t
	if not trust.has(key(a, b)):
		trust[key(a, b)] = TRUST_INITIAL


func adjust_trust(a: String, b: String, delta: int) -> void:
	var k := key(a, b)
	trust[k] = clampi(int(trust.get(k, TRUST_INITIAL)) + delta, 0, TRUST_MAX)


## ---------------------------------------------------------------- 위협도
##
## §8.1  위협도 = 대상 실동원 / 자국 실동원 + 인접도 보정 + 확장 속도 + 적대 여부
##
## ⚠ **확장 속도와 적대 여부는 아직 넣지 않았다.** 그 둘을 재려면
## 세력별 이력이 필요하다 — 미구현으로 남긴다.
static func threat_milli(own_mob: int, foe_mob: int, adjacent: bool) -> int:
	if own_mob <= 0:
		return THREAT_SURRENDER_MILLI
	var t := foe_mob * 1000 / own_mob
	if adjacent:
		t += THREAT_ADJACENT_MILLI
	return t


## 그 세력이 견제 연합을 원하는가 (F-07)
static func wants_coalition(threat: int) -> bool:
	return threat > THREAT_COALITION_MILLI


## 동맹 수락 여부.
##
## **공동의 위협이 있어야 손을 잡는다.** 둘 다 같은 상대를 2.0 초과로 보면
## 이해가 일치한다 — 손유 동맹이 성립하는 조건이 정확히 이것이다.
## 신뢰도가 바닥이면 거절한다 — 배신 기록이 영구 계승되기 때문이다 (§4.5).
func accepts(a: String, b: String, threat_a: int, threat_b: int) -> bool:
	if trust_of(a, b) < 200:
		return false
	return wants_coalition(threat_a) and wants_coalition(threat_b)


## 관계를 한 단계 올린다. 군사동맹이 상한.
func escalate(a: String, b: String) -> int:
	var t := mini(tier_of(a, b) + 1, Tier.군사동맹)
	set_tier(a, b, t)
	return t


func to_dict() -> Dictionary:
	return {"tiers": tiers.duplicate(), "trust": trust.duplicate()}
