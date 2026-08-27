class_name Hegemony
extends RefCounted

## 패권 압력(Hegemony Pressure) — 0~100 (function-events.md §0.3-②)
##
## **매 Grand 주기마다 전 세력에 대해 산출한다** (`ai-design.md` §8.1).
##
## > **「높음」 구간이 10점으로 좁은 것은 의도다.** 패권은 중간에 오래 머물지 않는다.
## > 견제 연합이 열리는 순간과 다수가 동시에 등을 돌리는 순간 사이가 짧아야
## > **「강해지면 곧바로 포위된다」**가 체감된다.
##
## 2026-08-25 신설. 그때까지 이 눈금은 **문서에만 있었고**,
## 그래서 **조조가 강해질수록 아무 반작용도 없었다** —
## 역사 재현율이 84% 로 굳은 원인 하나가 여기다.

const MIN: int = 0
const MAX: int = 100

## 유효 세력 하한 — 전체 실동원 합의 10% (`world-state.md` §4.0)
const EFFECTIVE_PCT: int = 10


## ---------------------------------------------------------------- 구간
##
## 구간 하한 → [명칭, 결과]
const BANDS: Array = [
	[60, "극대", "다수 세력이 동시 적대 전환"],
	[50, "높음", "견제 연합 결성 조건 개방 ([F-07])"],
	[35, "중", "인접 세력 간 상호 접근 시작"],
	[0, "낮음", "주변 세력이 개별 대응"],
]

## [F-07] 견제 연합이 열리는 하한
const COALITION_THRESHOLD: int = 50

## 다수가 동시에 등을 돌리는 하한
const HOSTILE_THRESHOLD: int = 60


static func band(value: int) -> String:
	for b in BANDS:
		if value >= int(b[0]):
			return String(b[1])
	return "낮음"


## ---------------------------------------------------------------- 우위 가산
const BONUS_EMPEROR: int = 10        # 황제 또는 상징(옥새) 보유
const BONUS_LAND_LEAD: int = 5       # 영토 점유율이 실동원 점유율보다 10%p 이상 높음
const BONUS_TALENT: int = 8          # 인재 밀도 1위 (1급 이상 인물 수)
const BONUS_DIPLOMACY: int = 5       # 외국 동맹 또는 책봉 보유

const LAND_LEAD_GAP_PCT: int = 10

## ---------------------------------------------------------------- 명분 침해 가산
##
## **황제 시해가 +30 으로 단일 최대다.** [F-02] 의 천명 −45 와 짝을 이룬다 —
## 「왜 조조는 황제를 시해하지 않는가」의 답이 두 수치에 걸쳐 있다.
const VIOLATION := {
	"황제폐립": 20,
	"참칭": 25,
	"수도소각": 15,
	"황제시해": 30,
}


## 기저 점유율 — 전 **유효** 세력 실동원 합에서의 몫.
##
## **유효 세력만 분모에 넣는다** (`world-state.md` §4.0).
## 그러지 않으면 소국이 늘어날수록 최강자의 압력이 희석된다 —
## **패권은 「몇 명이 있는가」가 아니라 「누가 얼마나 쥐었는가」다.**
static func base_share(mobilized_by_faction: Dictionary, fid: String) -> int:
	var total := 0
	var keys: Array = mobilized_by_faction.keys()
	keys.sort()                                  # **순회 순서 고정**
	for k in keys:
		total += int(mobilized_by_faction[k])
	if total <= 0:
		return 0
	var floor_v := total * EFFECTIVE_PCT / 100
	var eff_total := 0
	for k in keys:
		if int(mobilized_by_faction[k]) >= floor_v:
			eff_total += int(mobilized_by_faction[k])
	if eff_total <= 0:
		return 0
	return int(mobilized_by_faction.get(fid, 0)) * 100 / eff_total


## 패권 압력.
##
## `bonuses` 는 우위 가산 플래그 {"황제": bool, "영토": bool, "인재": bool, "외교": bool},
## `violations` 는 명분 침해 이름의 배열이다.
static func pressure(mobilized_by_faction: Dictionary, fid: String,
		bonuses: Dictionary = {}, violations: Array = []) -> int:
	var v := base_share(mobilized_by_faction, fid)
	if bool(bonuses.get("황제", false)):
		v += BONUS_EMPEROR
	if bool(bonuses.get("영토", false)):
		v += BONUS_LAND_LEAD
	if bool(bonuses.get("인재", false)):
		v += BONUS_TALENT
	if bool(bonuses.get("외교", false)):
		v += BONUS_DIPLOMACY
	for name in violations:
		v += int(VIOLATION.get(String(name), 0))
	return clampi(v, MIN, MAX)


## 영토 점유율이 실동원 점유율보다 10%p 이상 높은가.
##
## **넓은데 약한 세력**을 잡아낸다 — 원소가 그랬고, 유표가 그랬다.
## 「가진 것에 비해 못 쓴다」가 주변에는 **기회**로 보인다.
static func land_lead(land_by_faction: Dictionary,
		mobilized_by_faction: Dictionary, fid: String) -> bool:
	var lt := 0
	var mt := 0
	var keys: Array = land_by_faction.keys()
	keys.sort()
	for k in keys:
		lt += int(land_by_faction[k])
		mt += int(mobilized_by_faction.get(k, 0))
	if lt <= 0 or mt <= 0:
		return false
	var ls := int(land_by_faction.get(fid, 0)) * 100 / lt
	var ms := int(mobilized_by_faction.get(fid, 0)) * 100 / mt
	return ls - ms >= LAND_LEAD_GAP_PCT


static func opens_coalition(value: int) -> bool:
	return value >= COALITION_THRESHOLD


static func turns_hostile(value: int) -> bool:
	return value >= HOSTILE_THRESHOLD
