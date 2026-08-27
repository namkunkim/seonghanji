class_name Events
extends RefCounted

## 기능 이벤트 — 발동 판정 (function-events.md)
##
## **40종 중 17종이 지금 걸린다.** 나머지 23종은 인물 계층이 필요하다 —
## 성향 · 충성도 · 지력 · 연령이 코어에 없다.
##
## ```
## 지금 걸리는 것   눈금 다섯 + 실동원 + 권역 + 회랑 + 함대 + 군주 유형
## 아직 못 거는 것   인물 17종 · 상징/옥새 3종 · 찬탈 진행도 1종 · 첩보 2종
## ```
##
## 2026-08-25 신설. 그때까지 `Sim._advance_one_tick` 의 ⑥ 자리가 비어 있었다 —
## **「미발동 이벤트 0종」이 M0 의 마지막 「판정 불가」 지표였다.**

## 판정 주기. **Grand(계절)마다 본다** — 매 틱 40종을 굴릴 이유가 없다
const CHECK_PERIOD_TICKS: int = Strategy.GRAND_PERIOD_TICKS

## 같은 이벤트가 같은 세력에게 연달아 터지지 않게 하는 냉각 (틱)
const COOLDOWN_TICKS: int = Strategy.GRAND_PERIOD_TICKS * 4

## ---------------------------------------------------------------- 임계
##
## 전부 `function-events.md` 의 발동 조건에서 그대로 옮긴 값이다.

const F02_SYMBOL_SHARE_PCT: int = 8         # 실동원 ≤ 전 유효 합의 8%
const F05_CORRIDOR_HUBS: int = 2            # 회랑 2개 이상 접속 권역
const F05_MOBILIZED: int = 40
const F07_COALITION_RATIO_PCT: int = 40     # 견제 합 ≥ 최강자 × 0.4
const F07_TRUST_MIN: int = 300              # 상호 신뢰도 ≥ 30 (0~1000 눈금)
const F07_LEADER_MANDATE: int = 4
const F09_SPLIT_RATIO_PCT: int = 90         # 최강자 ≥ 연합 합 × 0.9
const F10_STABLE_MONTHS: int = 18
const F10_DECAY_PCT_PER_MONTH: int = 3
const F10_DECAY_CAP_PCT: int = 40
const F12_TRUST_MAX: int = 350              # 동맹 신뢰도 ≤ 35
const F12_COMMITTED_PCT: int = 60           # 주력 60% 이상이 타 전선
const F14_RESTORE_PRESSURE: int = 60        # 공동 위협 패권 압력 ≥ 60
const F14_SHARE_PCT: int = 10
const F15_ATTACK_RATIO_PCT: int = 150       # 공격측 ≥ 방어측 × 1.5
const F17_MOBILIZED: int = 30
const F25_LAST_STAND_DEN: int = 3           # 실동원 ≤ 적의 1/3
const F36_DEFICIT_PCT: int = 80             # 실효 국력 ≤ 유지점 총합 × 0.8
const F37_CAPITAL_RATIO_PCT: int = 250      # 적 ≥ 주권역 방어 × 2.5
const F39_REVOLT_STABILITY: int = 30        # 후방 권역 안정도 ≤ 30
const F39_COMMITTED_PCT: int = 60
const F40_MANDATE: int = 40


## 지금 구현된 이벤트 — **순서를 고정한다** (결정론)
const IMPLEMENTED: Array[String] = [
	"F-02", "F-05", "F-07", "F-09", "F-10", "F-12", "F-13", "F-14",
	"F-15", "F-17", "F-23", "F-25", "F-27", "F-36", "F-37", "F-39", "F-40",
]

## 인물 계층이 서야 걸리는 것 — **미발동 지표에서 「미구현」으로 따로 센다**
const NEEDS_CHARACTERS: Array[String] = [
	"F-04", "F-16", "F-18", "F-19", "F-20", "F-21", "F-22", "F-24",
	"F-26", "F-28", "F-29", "F-30", "F-31", "F-32", "F-33", "F-34", "F-38",
]

## 그 밖의 미구현 — 상징/옥새 · 찬탈 진행도 · 분배 협상 · 토호 접촉
const NEEDS_OTHER: Array[String] = ["F-01", "F-03", "F-06", "F-08", "F-11", "F-35"]


## 회랑을 두 개 이상 끼는 권역인가. [F-05] · [F-15] 의 「요충」이다.
static func is_hub(data: GameData, rid: String) -> bool:
	var n := 0
	for h in data.regions[rid].get("routes_hosted", []):
		if data.is_corridor(String(h)):
			n += 1
	return n >= F05_CORRIDOR_HUBS


## 전 유효 세력 실동원 합에서의 몫(%).
static func share_pct(mobs: Dictionary, fid: String) -> int:
	var total := 0
	var keys: Array = mobs.keys()
	keys.sort()
	for k in keys:
		total += int(mobs[k])
	if total <= 0:
		return 0
	return int(mobs.get(fid, 0)) * 100 / total


## [F-10] 연합 해체 확률(%). 18개월 뒤부터 매월 3%p, 상한 40%.
##
## > **오래 간 연합일수록 깨지기 쉽다.** 공동의 적이 약해지면 분배가 시작된다.
static func coalition_decay_pct(months: int) -> int:
	if months <= F10_STABLE_MONTHS:
		return 0
	return mini((months - F10_STABLE_MONTHS) * F10_DECAY_PCT_PER_MONTH,
		F10_DECAY_CAP_PCT)
