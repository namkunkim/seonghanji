class_name Scheme
extends RefCounted

## 계략 (combat.md §5)
##
## **계략은 약자의 무기다** (§5.4). 확실해서는 안 되지만 봉쇄되어서도 안 된다 —
## 간파 상한 60% · 성공률 상한 90% 가 그 두 문장을 양쪽에서 잡는다.
##
## 2026-08-28 신설. 그때까지 **코어가 §5 를 한 번도 읽지 않았다** —
## `tests/verify_chibi.gd` 가 적벽 검산을 손으로 재현할 뿐이었고,
## `core/` 어디에도 계략이 없었다. 「사기 108.2 의 고양 구간이 위장 항복을
## 47% 에서 37% 로 깎는다」는 §5.7 의 결론이 **코드에서는 일어나지 않았다.**
##
## **이번 세션에 일곱 번째로 만난 같은 패턴이다** —
## 회랑 넷 · 훈련도 · 기술 · 천명 · 패권 압력 · 인물 · 그리고 계략.
##
## 모든 확률을 **1/1000 퍼센트(밀리퍼센트) 정수**로 다룬다 — 부동소수 금지 (§2.3).
## 17.6% = 17600. §5.7 의 소수 첫째 자리가 정수로 정확히 떨어져야 하기 때문이다.


## ---------------------------------------------------------------- 계략 7종
##
## §5.1 목록. **열거 순서를 고정한다** — 선택 순회가 결정론의 전제다 (§2.3).
enum Kind { FIRE, AMBUSH, DISCORD, JAM, FALSE_SURRENDER, LURE, DECAPITATE }

const NAMES: Array[String] = [
	"화공", "매복", "이간", "교란", "위장 항복", "유인", "참수",
]

## 시전 가능 페이즈 (§5.1 · §5.3). 0=접적 1=포화 2=교전 3=강습 4=결착
const PHASES: Array = [
	[1],            # 화공        ②
	[0],            # 매복        ①
	[0, 1, 2],      # 이간        ①~③
	[0, 1],         # 교란        ①②
	[1, 2],         # 위장 항복   ②③
	[2, 4],         # 유인        ③⑤
	[3],            # 참수        ④
]

## 기본치 (§5.3). 밀리퍼센트.
##
## **기본치가 낮을수록 지력에 더 의존한다** — 위장 항복과 참수는 아무나 못 한다.
## 교란은 반대다: 기본치가 높고 지력 계수가 낮다 —
## **장비의 문제이지 사람의 문제가 아니다.**
const BASE_MILLI: Array[int] = [
	25000, 30000, 20000, 40000, 15000, 35000, 15000,
]

## 지력 계수 (§5.3). (시전측 최고 지력 − 대상 지휘관 지력) 에 곱한다.
## 0.5 → 500 (지력 1 차이당 0.5%p)
const WITS_COEFF_MILLI: Array[int] = [500, 500, 600, 400, 500, 500, 400]

## 성공률 범위 (§5.3) [5 ~ 90]
const SUCCESS_MIN_MILLI: int = 5000
const SUCCESS_MAX_MILLI: int = 90000

## 간파 범위 (§5.4) [5 ~ 60]
##
## > **상한을 60%로 잡았다.** 참모를 잘 갖춘 쪽이 계략에 완전 면역이 되면
## > 열세 세력에게 승로가 사라진다.
const DETECT_MIN_MILLI: int = 5000
const DETECT_MAX_MILLI: int = 60000
const DETECT_BASE_MILLI: int = 20000
const DETECT_WITS_COEFF_MILLI: int = 400


## ---------------------------------------------------------------- 대상 사기 구간
##
## §5.3 보정항. **§1.1 이 값 없이 「계략 피격 확률 상승」이라고만 적어 둔 칸**이다.
##
## > 이 항 하나로 계략이 **결정타가 아니라 추격타**가 된다.
## > 멀쩡한 함대에는 잘 걸리지 않고, 이미 흔들린 함대에는 잘 걸린다.
##
## 고양은 동요의 거울이다 — ±10 대칭, 붕괴 위험에서만 +20.
static func morale_band_milli(morale: int) -> int:
	if morale >= 101:
		return -10000                 # 고양 125~101
	if morale >= 70:
		return 0                      # 정상 100~70
	if morale >= 40:
		return 10000                  # 동요 69~40
	return 20000                      # 붕괴 위험 39~20 (19 이하는 이미 붕괴다)


## ---------------------------------------------------------------- 전자전함
##
## §5.3. 비율(%p) × 0.5 [상한 +20] · **교란만** ×1.0 [상한 +40].
## 표준 편성의 전자 10% 가 화공·위장 항복에 +5 를 준다 (§5.7).
static func ew_bonus_milli(kind: int, ew_pct: int) -> int:
	if kind == Kind.JAM:
		return mini(ew_pct * 1000, 40000)
	return mini(ew_pct * 500, 20000)


## ---------------------------------------------------------------- 지형 (§5.3 · §4.2)
const TERRAIN_BASE_ROUTE_AMBUSH_MILLI: int = 50000    # 기저 항로 — 매복

## 회랑 출구 — 매복. **+30 → +15 (2026-08-28, M0 밸런스 · combat.md §10 검토 14).**
## 원안 +30은 조조가 공격측으로 회랑을 지날 때 방어측 매복 피격률을 39.2%까지
## 끌어올렸다(비회랑 공격 24.0%의 1.6배) — 그의 공세 69%가 회랑을 통하므로
## 「봉쇄는 성립하되 봉쇄만으로는 이길 수 없다」(불가침 §2-4)의 반대편이 됐다.
## **회랑 전투력(§3.3 일부당관)·통과 비용은 그대로다** — 여기서 낮춘 것은
## 계략 판정 한 항목뿐이다.
const TERRAIN_CORRIDOR_EXIT_AMBUSH_MILLI: int = 15000
const TERRAIN_DENSE_FIRE_MILLI: int = 20000           # 밀집 진형 — 화공

## 「계략 중시」 방침 (§5.3)
const FOCUS_MILLI: int = 10000

## 위장 항복이 여는 것 — **이어지는 계략 +20** (§5.5)
const LINKED_MILLI: int = 20000


## 지력 80 이상 참모형 동승 — 1인당 +5 [상한 +15] (§5.3)
static func staff_bonus_milli(staff80: int) -> int:
	return mini(maxi(staff80, 0) * 5000, 15000)


## ---------------------------------------------------------------- 특성 (§5.3 · §5.4 · §9)
##
## **특성은 이름이 아니라 키워드로 찾는다.** `characters.json` 의 `traits` 는
## 문서의 특성 칸을 통째로 담고 있어(「미주랑」 화공 계열 계략 +50%. 대회전 지휘 특화)
## 부분 일치가 아니면 걸리지 않는다.

## 시전 특성 (§5.3)
const TRAIT_MIJURANG: String = "미주랑"          # 주유 — 화공 +50
const TRAIT_GWIMO: String = "귀모"               # 곽가 — ① 계략 +30
const TRAIT_GOYUK: String = "고육계"             # 황개 — 위장 항복 +25
const TRAIT_SINGI: String = "신기묘산"           # 제갈량 — 전 계략 +20

## 간파 특성 (§5.4)
const TRAIT_EUNGBYEON: String = "응변"           # 진태 +35
const TRAIT_SIBI: String = "십이기책"            # 순유 +30

## 가후는 §5.4 표에 특성 이름 없이 인물로 올라 있다. **이름으로 건다.**
const DETECT_BY_NAME := {"가후": 25000}


static func has_trait(traits: Array, key: String) -> bool:
	for t in traits:
		if String(t).contains(key):
			return true
	return false


## 시전 특성 보정 (§5.3). 밀리퍼센트.
static func trait_bonus_milli(kind: int, phase: int, traits: Array) -> int:
	var v := 0
	if kind == Kind.FIRE and has_trait(traits, TRAIT_MIJURANG):
		v += 50000
	if phase == 0 and has_trait(traits, TRAIT_GWIMO):
		v += 30000
	if kind == Kind.FALSE_SURRENDER and has_trait(traits, TRAIT_GOYUK):
		v += 25000
	if has_trait(traits, TRAIT_SINGI):
		v += 20000
	return v


## 간파 특성 보정 (§5.4). 밀리퍼센트.
##
## **곽가「귀모」는 양쪽에 있다** — ① 계략 +30 이면서 간파 +25 다.
## 「적 의도 예측 공개」(§9)가 두 방향으로 작동하는 것이지 중복 기재가 아니다.
static func detect_trait_bonus_milli(traits: Array, name: String = "") -> int:
	var v := 0
	if has_trait(traits, TRAIT_EUNGBYEON):
		v += 35000
	if has_trait(traits, TRAIT_SIBI):
		v += 30000
	if has_trait(traits, TRAIT_SINGI):
		v += 30000
	if has_trait(traits, TRAIT_GWIMO):
		v += 25000
	v += int(DETECT_BY_NAME.get(name, 0))
	return v


## ---------------------------------------------------------------- 성공률 (§5.3)
##
##     계략 성공률(%) = 기본치
##                    + (시전측 최고 지력 − 대상 지휘관 지력) × 지력 계수
##                    + 대상 사기 구간 보정
##                    + 전자전함 보정
##                    + 지형 보정
##                    + 특성 보정
##                    + 방침 보정                        [5 ~ 90]
##
## **시전측 최고 지력은 함대에 편성된 인물 중 최고값이다** —
## 실행자와 입안자가 다를 수 있다. 황개가 배를 몰았고, 계략은 주유의 것이다.
static func success_chance_milli(kind: int, phase: int,
		caster_wits: int, target_wits: int, target_morale: int,
		ew_pct: int = 0, terrain_milli: int = 0,
		traits: Array = [], staff80: int = 0,
		scheme_focus: bool = false, linked_milli: int = 0) -> int:
	var v: int = BASE_MILLI[kind]
	v += (caster_wits - target_wits) * WITS_COEFF_MILLI[kind]
	v += morale_band_milli(target_morale)
	v += ew_bonus_milli(kind, ew_pct)
	v += terrain_milli
	v += trait_bonus_milli(kind, phase, traits)
	v += staff_bonus_milli(staff80)
	if scheme_focus:
		v += FOCUS_MILLI
	v += linked_milli
	return clampi(v, SUCCESS_MIN_MILLI, SUCCESS_MAX_MILLI)


## ---------------------------------------------------------------- 간파 (§5.4)
##
##     간파 확률(%) = 20 + (간파측 최고 지력 − 시전측 최고 지력) × 0.4 + 특성   [5 ~ 60]
##
## **계략은 간파 판정을 먼저 굴린다.** 통과해야 성공률 판정으로 간다.
##
## > **정욱은 17.6%였다.** 원전에서 그는 황개의 항복을 의심했고 조조는 듣지 않았다.
## > 공식이 그 장면을 확률로 되돌려준다 — 의심한 쪽이 옳았고, 그래도 낮은 쪽이었다.
static func detect_chance_milli(detector_wits: int, caster_wits: int,
		traits: Array = [], detector_name: String = "") -> int:
	var v := DETECT_BASE_MILLI
	v += (detector_wits - caster_wits) * DETECT_WITS_COEFF_MILLI
	v += detect_trait_bonus_milli(traits, detector_name)
	return clampi(v, DETECT_MIN_MILLI, DETECT_MAX_MILLI)


## 실제 발동 확률 = (1 − 간파) × 성공률. §5.5-b 표의 「발동 확률」 열이 이것이다.
static func trigger_chance_milli(detect_milli: int, success_milli: int) -> int:
	return (100000 - detect_milli) * success_milli / 100000


## 간파 인물 1인은 전투당 2회까지 간파한다 (§5.4)
const DETECTS_PER_PERSON: int = 2

## 시전 횟수 = 3 + (지력 80 이상 참모형 인물 수) [상한 5] · 페이즈당 1회 (§5.3)
const ATTEMPTS_BASE: int = 3
const ATTEMPTS_MAX: int = 5


static func attempts_allowed(staff80: int) -> int:
	return mini(ATTEMPTS_BASE + maxi(staff80, 0), ATTEMPTS_MAX)


## ---------------------------------------------------------------- 효과 (§5.5)
##
## 손실률(밀리 %). 화공 20% · 매복 5% · 나머지는 손실을 주지 않는다.
const EFFECT_LOSS_MILLI: Array[int] = [20000, 5000, 0, 0, 0, 0, 0]

## 피격 측 사기 사건 가산 E (§1.3 E 표).
## 위장 항복 40 · 화공 25 · 매복 15.
const EFFECT_EVENT: Array[int] = [25, 15, 0, 0, 40, 0, 0]

## 시전 측 사기 페널티 (§5.4) — 간파당하면 15, 간파되지 않고 실패하면 5.
const EVENT_DETECTED: int = 15
const EVENT_FAILED: int = 5

## 매복 — 적 ② 손실률 ×1.5 (§5.5). 1/1000.
const AMBUSH_NEXT_LOSS_MILLI: int = 1500

## 이간 — 적 지휘관 보정 −60%, 3페이즈 지속 (§5.5)
const DISCORD_KEEP_MILLI: int = 400
const DISCORD_PHASES: int = 3


## 이간에 걸린 지휘관의 실효 스탯. **보정의 60% 가 사라지는 것이지
## 스탯이 사라지는 것이 아니다** — 50 이 「보정 없음」이므로 그쪽으로 당긴다.
static func discorded_stat(stat: int) -> int:
	return 50 + (stat - 50) * DISCORD_KEEP_MILLI / 1000


## **연계 계략은 중첩하지 않는다** (§1.3).
## 위장 항복이 화공의 전제로 쓰인 경우처럼 한 계략이 다른 계략의 조건을 열면
## **큰 쪽 그대로 + 작은 쪽 ×0.5** — 40 + 12.5 = 52.5. 밀리로 돌려준다.
##
## 그러지 않으면 계략 두 개로 어떤 함대든 즉사하고 ①~③ 의 축적이 무의미해진다.
static func linked_event_milli(a: int, b: int) -> int:
	var hi := maxi(a, b)
	var lo := mini(a, b)
	return hi * 1000 + lo * 500


## ---------------------------------------------------------------- 연영도 (§5.5-b)
##
## **화공 ×3은 지형이 아니라 시간이 연다.**
##
## > 유비의 연영이 탄 것은 협도를 지났기 때문이 아니라 **거기서 여러 달을 보냈기** 때문이다.
##
##     연영도 += 1 / 게임 내 1개월 × 방어측 계수 × 원정측 방침 계수
##                                 − 협도 너머 확보 권역 수

const SPRAWL_YUKSON_MILLI: int = 2000        # 육손「인내」 — 버티는 것이 그의 능력이다
const SPRAWL_PATIENT_MILLI: int = 1400       # 「인내」급 대체 지휘관 (ACT 8 규칙)
const SPRAWL_STANDARD_MILLI: int = 1000      # 그 외 방어 지휘관
const SPRAWL_ABSENT_MILLI: int = 600         # 방어 지휘관 부재
const SPRAWL_CAUTIOUS_MILLI: int = 500       # 원정측 「신중」 — 분산 주둔

## 임계. **경고 없이 죽지 않는다** — 3 진입과 6 진입은 §2.2 분기점 알림 대상이다.
const SPRAWL_ALERT: Array[int] = [3, 6]


## 한 달치 증가분(1/1000). 육손 방어 · 방침 보통 · 확보 0 이면 +2.0 —
## **육손이 방어하면 반년이 석 달 만에 온다.** 「인내」가 시계를 두 배로 돌린다.
static func sprawl_gain_milli(defender_milli: int, doctrine_milli: int,
		secured_regions: int) -> int:
	return defender_milli * doctrine_milli / 1000 - secured_regions * 1000


## 연영도 구간. 0 = 0~2 · 1 = 3~5 · 2 = 6 이상
static func sprawl_band(sprawl: int) -> int:
	if sprawl >= 6:
		return 2
	if sprawl >= 3:
		return 1
	return 0


## 구간별 화공 성공률 가산 (§5.5-b). +0 / +10 / +25
const SPRAWL_SUCCESS_MILLI: Array[int] = [0, 10000, 25000]

## 구간별 화공 피해 배율 (1/1000). ×1.2 / ×2.0 / ×3.0
##
## **이릉협도만 ×3.0 에 닿는다.** 다른 대회랑은 ×2.0 이 상한이다 —
## 삼협처럼 좌우가 막힌 곳이 아니기 때문이다.
const SPRAWL_DAMAGE_MILLI: Array[int] = [1200, 2000, 3000]
const SPRAWL_DAMAGE_CAP_ORDINARY: int = 2000


## 화공 피해 배율 (§5.5). 밀집 진형 ×1.5 · 회랑 ×1.2 ·
## 대회랑 너머 대치는 연영도가 정한다 (최대 ×3.0).
##
## **협도에 들어섰다고 해서 ×3 이 열리지 않는다.** §4.2 의 「화공 피해 ×3」은 상한이고,
## 실제 배율은 대치가 얼마나 길어졌는가로 정해진다.
static func fire_damage_milli(dense: bool, corridor: bool,
		sprawl: int = -1, ravine: bool = false) -> int:
	if sprawl >= 0:
		var m: int = SPRAWL_DAMAGE_MILLI[sprawl_band(sprawl)]
		if not ravine:
			m = mini(m, SPRAWL_DAMAGE_CAP_ORDINARY)
		return m
	if dense:
		return 1500
	if corridor:
		return 1200
	return 1000


## ---------------------------------------------------------------- 성향 (§5.6)
##
## **성향은 성공률이 아니라 선택에 건다.**
##
## > 성공률에 성향을 걸면 즉시 모순이 생긴다 — **황개는 절의인데 고육계를 실행했다.**
## > 계략의 성패는 지력이 정하고, 계략을 고르는 것은 성향이 정한다.
##
## **누구의 성향인가 — 입안자다.** 함대 지휘관에 건다.
## 실행자(황개 절의 ×0.6)에 걸면 적벽 고육계의 선택 가중이 0.54 로 떨어져
## AI 가 그것을 거의 고르지 않는다. 계략은 주유(명사 ×0.9)의 것이다.
const DISPOSITION_MILLI := {
	"절의": 600, "명사": 900, "실무": 1000, "무뢰": 1200, "야심": 1300,
}


static func disposition_milli(disposition: String) -> int:
	return int(DISPOSITION_MILLI.get(disposition, 1000))


## §7.3 조건 충족 가산 (ai-design.md). 0.4 → 400
const CONDITION_BONUS_MILLI: int = 400

## 기본 가중 (ai-design.md §7.4 표의 「기본 0.5 가정」)
const BASE_WEIGHT_MILLI: int = 500


## 계략 선택 가중 = (기본 가중 + 0.4) × 성향 계수 (ai-design.md §7.4)
##
## **순서를 뒤집으면 안 된다.** 곱셈을 먼저 하면 조건이 충족되지 않은 계략에도
## 성향이 걸려 야심형 지휘관이 화공 조건이 없는데 화공을 고른다.
##
## `delegated` 가 거짓이면 성향이 걸리지 않는다 — **플레이어가 직접 지시하면
## 관우도 위장 항복을 시전한다. 다만 그것은 관우의 선택이 아니다** (§5.6).
## AI 에게 위임은 유일한 상태이므로 AI 는 항상 참이다 (ai-design.md §7.4-②).
static func selection_weight_milli(condition_met: bool, disposition: String,
		delegated: bool = true, base_milli: int = BASE_WEIGHT_MILLI) -> int:
	var w := base_milli
	if condition_met:
		w += CONDITION_BONUS_MILLI
	if delegated:
		w = w * disposition_milli(disposition) / 1000
	return w


## ---------------------------------------------------------------- 굴림
##
## **밀리퍼센트 굴림은 1회 소비다** (§2.3 ③). `percent()` 와 소비량이 같으므로
## 정밀도를 올려도 소비 순서가 흔들리지 않는다.
static func roll_milli(rng: RngStream, chance_milli: int) -> bool:
	return rng.below(100000) < chance_milli


## ---------------------------------------------------------------- 캠페인 배선 범위
##
## **효과가 걸릴 자리가 있는 계략만 캠페인이 시전한다.** 두 종은 보류다.
##   - **교란** — 「적 지시 1회 무작위화」(§5.5). 전투 지시 체계가 S3 이후다
##   - **참수** — §5.5 가 스스로 §6.2-b 호위 판정으로 이관했다. 그 판정이 아직 없다
##
## 산식은 위에 전부 있다. **막힌 것은 효과이지 판정이 아니다.**
const CAMPAIGN_ENABLED: Array[int] = [
	Kind.FIRE, Kind.AMBUSH, Kind.DISCORD, Kind.FALSE_SURRENDER, Kind.LURE,
]


## 이 페이즈에 시전할 수 있는가 (§5.1)
static func allows_phase(kind: int, phase: int) -> bool:
	return PHASES[kind].has(phase)
