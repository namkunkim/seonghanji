class_name Tech
extends RefCounted

## 기술 개발 — 3축 5단계 (domestic.md §5.6 · DECISIONS.md V-34)
##
## **부품이 아니라 단계다.** 플레이어는 「무엇을 달까」를 고르지 않는다 —
## 단계가 오르면 전 함대에 적용된다. Stellaris 에서 공방 상쇄는 가져오고
## 부품 선택은 버렸다: 함종 6 × 진형 7 × 상성 5각 위에 부품표를 얹으면
## `ship-specs.md` 검토 10 의 학습 부담이 터진다.
##
## **기술은 땅의 것이 아니라 나라의 것이다.** 세력 명령이며 45 권역에 흩어지지 않는다.

## 축 순서를 **고정한다** — 순회 순서가 결정론의 전제다 (dev-requirements.md §2.3)
const AXES: Array[String] = ["화력", "방어", "특수"]

const MAX_LEVEL: int = 5

## 단계 n 의 비용 = n × 4,000 · 소요 = n × 2개월.
##
## **세력 크기에 비례하지 않는 정액이다.** 그래야 작은 세력이 기술로 따라잡을 수 있고
## 「소수정예 특수병기」라는 촉의 노선이 성립한다 (design-overview.md §7).
const COST_PER_LEVEL: int = 4000
const MONTHS_PER_LEVEL: int = 2

## 촉 — 「기술 개발 속도 +30%」 (region-power.md §4). 소요 ×0.7
const FAST_PCT: int = 70


## 다음 단계로 가는 비용. 이미 최대면 -1.
static func cost(current_level: int) -> int:
	if current_level >= MAX_LEVEL:
		return -1
	return (current_level + 1) * COST_PER_LEVEL


## 다음 단계로 가는 소요(틱). 이미 최대면 -1.
static func ticks(current_level: int, fast: bool = false) -> int:
	if current_level >= MAX_LEVEL:
		return -1
	var months := (current_level + 1) * MONTHS_PER_LEVEL
	var t := months * GameClock.TICKS_PER_MONTH
	if fast:
		t = t * FAST_PCT / 100
	return t


## 세 축을 5단계까지 다 올리는 총비용. **세 축을 다 가질 수는 없다.**
static func full_cost() -> int:
	var c := 0
	for lv in MAX_LEVEL:
		c += (lv + 1) * COST_PER_LEVEL
	return c * AXES.size()


## ---------------------------------------------------------------- 전력 계수
##
## **화력과 방어는 서로를 뺀다** (combat.md §1.4-c).
##
## > **기술은 앞선 만큼만 이롭다.** 절대값이 아니라 격차가 값이다.
## > 5단계 대 5단계는 계수 1.000 이다 — `ship-specs.md` §5.4 의
## > 「절대 우위 없음」이 기술 축에서도 성립하고, **폭주를 막는다.**
## > 큰 세력이 기술로도 앞서면 국력 격차가 곱해진다. 뺄셈이면
## > 따라잡은 쪽이 즉시 무효화한다.
const EFF_MIN: int = -2
const EFF_MAX: int = 5
const STEP_MILLI: int = 60


## 실효 단계. −2 ~ +5 로 절단한다.
static func effective_level(fire: int, enemy_defense: int) -> int:
	return clampi(fire - enemy_defense, EFF_MIN, EFF_MAX)


## 전력 계수(1/1000). 0.880 ~ 1.300
static func power_milli(fire: int, enemy_defense: int) -> int:
	return 1000 + effective_level(fire, enemy_defense) * STEP_MILLI


## ---------------------------------------------------------------- 특수 무기
##
## 이름은 원전에 있다 (`ship-specs.md` §1 이중 레이어).
##   광자 어뢰 = **화선** — 적벽의 황개. 불붙은 배를 흘려보냈다
##   기뢰      = **철쇄** — 오가 강에 쇠사슬을 걸었다
##
## **소모품은 늘리지 않는다** (§0.1-2). 화선은 미사일 재고를 쓰고(4발 = 1발),
## 철쇄는 전투 소모품이 아니라 권역 설치물이다.
const UNLOCK_FIRESHIP: int = 2      # 화선
const UNLOCK_CHAIN: int = 4         # 철쇄

## 화선 1발이 먹는 미사일
const FIRESHIP_MISSILE_COST: int = 4

## 화선 명중 시 사기 감소
const FIRESHIP_MORALE: int = -12


static func has_fireship(special_level: int) -> bool:
	return special_level >= UNLOCK_FIRESHIP


static func has_chain(special_level: int) -> bool:
	return special_level >= UNLOCK_CHAIN


## **철쇄는 회랑·관문에 설치할 수 없다** [불가침 ④].
##
## 회랑은 이미 통과 비용의 최대치이며 거기에 무엇을 더 얹어도 안 된다 —
## 「봉쇄는 성립하되 봉쇄만으로는 이길 수 없다」가 무너지기 때문이다.
##
## 그리고 원전이 그 한계를 이미 말해 두었다 —
## **왕준은 오의 철쇄를 큰 횃불로 태워 끊고 강을 내려갔다.**
static func can_lay_chain(data: GameData, rid: String) -> bool:
	for h in data.regions[rid].get("routes_hosted", []):
		# 이름이 아니라 정본 목록으로 판정한다 —
		# **이름으로 걸렀을 때 이릉협도에 철쇄를 깔 수 있었다** (2026-08-25).
		if data.is_corridor(String(h)):
			return false
	return true
