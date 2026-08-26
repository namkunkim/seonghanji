class_name Faction
extends RefCounted

## 세력 (region-power.md §3 · world-state.md §4)

var id: String = ""
var name: String = ""

## 본거지 성계. 명령과 함대가 여기서 출발한다
var capital_system: String = ""

## 보유 권역. **정렬을 유지한다** — 순회 순서가 결정론의 전제다 (§2.3)
var regions: Array[String] = []

## 군주 유형 (dispositions.md §4). 성격이 AI 가중치를 가른다
var lord_type: String = "실리형"

## 통치 체제 (region-power.md §3.4-b ④). 동원율에 직접 걸린다
var governance: String = "표준"

## 유랑 세력 특례 — 접경·신복속 미적용, 상한 0.80
var wandering: bool = false

## 살아 있는가. 권역을 전부 잃으면 소멸
var alive: bool = true

## ---------------------------------------------------------------- 경제
##
## 보유 자금. **세력 단위 단일 풀이다** — 권역별 창고를 두지 않는다.
## 45 권역 × 물류는 조작 부담을 배로 만든다 (domestic.md §5.2)
var treasury: int = 0

## 기술 단계. 화력 · 방어 · 특수 각 0~5 (domestic.md §5.6)
## **부품이 아니라 단계다.** 오르면 전 함대에 적용된다
var tech: Dictionary = {"화력": 0, "방어": 0, "특수": 0}

## 진행 중인 기술 개발. {"axis": "화력", "done_tick": 12345}
var tech_research: Dictionary = {}

## 기술 개발 속도 특성. 촉의 「+30%」 (region-power.md §4)
var tech_fast: bool = false

## 편성안 (ship-specs.md §7.2)
var plan: String = Economy.PLAN_DEFAULT


func add_region(rid: String) -> void:
	if not regions.has(rid):
		regions.append(rid)
		regions.sort()


func remove_region(rid: String) -> void:
	regions.erase(rid)
	if regions.is_empty():
		alive = false


## 실효 국력(1/1000). 전화 계수가 반영된다
func effective_milli(data: GameData, states: Dictionary) -> int:
	var sum := 0
	for rid in regions:
		var st: RegionState = states.get(rid)
		var w := 950 if st == null else st.war_damage_milli
		sum += data.region_power(rid) * w
	return sum


## **동원에 쓸 수 있는 실효 국력**(1/1000). 위임 권역은 절반만 센다.
##
## 이것이 위임 대가의 본체다 (domestic.md §3) —
## 자금은 오히려 여유가 생기지만 **함대 상한이 줄어 전선에 나갈 수 없다.**
## 조조가 하북을 전부 위임하면 재정은 편해지고 적벽에는 가지 못한다.
func effective_for_mobilization_milli(data: GameData, states: Dictionary) -> int:
	var sum := 0
	for rid in regions:
		var st: RegionState = states.get(rid)
		var w := 950 if st == null else st.war_damage_milli
		var v := data.region_power(rid) * w
		if st != null and st.delegated:
			v = v * Economy.DELEGATED_MOBILIZATION_PCT / 100
		sum += v
	return sum


## 동원율. 접경 수에서 산출한다 (region-power.md §3.4-b ①)
## **회랑 접경은 개방 접경의 6분의 1** — 「국경이 회랑뿐이면 수비 부담이 적다」
func mobilization(data: GameData, corridor_borders: int, open_borders: int) -> float:
	return Power.mobilization(open_borders, corridor_borders)


## 접경을 센다. 자기 권역과 인접했으나 자기 것이 아닌 권역의 수.
## 회랑·관문을 낀 접경은 따로 센다.
func count_borders(data: GameData) -> Array:
	var open_b := 0
	var cor_b := 0
	for rid in regions:
		for nb in data.region_adjacency.get(rid, []):
			if regions.has(nb):
				continue
			if _shares_choke(data, rid, nb):
				cor_b += 1
			else:
				open_b += 1
	return [open_b, cor_b]


## **그 접경이 회랑을 끼고 있는가.**
##
## 권역이 회랑을 하나 쥐고 있다고 해서 그 권역의 **모든** 접경이
## 회랑 접경인 것은 아니다. 낙양권은 호뢰관문을 쥐지만 병주 방면은
## 기저 항로다 — 두 접경의 수비 부담이 6배 다르다 (§3.4-b ①).
##
## 2026-08-25: 이것을 뭉뚱그렸다가 조조의 개방 접경이 0 으로 나와
## 동원율이 0.79 가 되었다 (문서 0.35).
static func _shares_choke(data: GameData, a: String, b: String) -> bool:
	var ha: Array = data.regions[a].get("routes_hosted", [])
	var hb: Array = data.regions[b].get("routes_hosted", [])
	for x in ha:
		if not ("회랑" in x or "관문" in x):
			continue
		if hb.has(x):
			return true
	return false


## 본거지에서 가장 먼 보유 권역까지의 **성계 단계**. 보급선의 길이다 (§3.4-b ③).
func expedition_hops(data: GameData, graph: Dictionary) -> int:
	if capital_system == "" or regions.is_empty():
		return 0
	var worst := 0
	for rid in regions:
		var sid := data.system_of(rid)
		if sid == capital_system:
			continue
		worst = maxi(worst, _hops(graph, capital_system, sid))
	return worst


## 성계 홉 수. 소요가 아니라 **단계**를 센다 —
## 회랑 소요는 이미 접경 부담(①)에 반영되어 있다.
static func _hops(graph: Dictionary, from_sys: String, to_sys: String) -> int:
	if from_sys == to_sys:
		return 0
	var seen := {from_sys: 0}
	var queue: Array[String] = [from_sys]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var d: int = seen[cur]
		var nbs: Array[String] = []
		for e in graph.get(cur, []):
			nbs.append(String(e["to"]))
		nbs.sort()                       # 순회 순서 고정
		for nb in nbs:
			if seen.has(nb):
				continue
			seen[nb] = d + 1
			if nb == to_sys:
				return d + 1
			queue.append(nb)
	return 99


## 실동원. 세계 상태 판정(V-27)의 입력이다.
## **네 항을 모두 반영한다** (§3.4-b ①②③④).
func mobilized(data: GameData, states: Dictionary,
		graph: Dictionary = {}, now_tick: int = 0) -> int:
	var b := count_borders(data)
	var nt := Power.newly_taken_burden_milli(states, regions, now_tick)
	var hops := expedition_hops(data, graph) if not graph.is_empty() else 1
	var rate := Power.mobilization_full_milli(b[0], b[1], nt, hops,
		governance, wandering)
	return effective_for_mobilization_milli(data, states) * rate / 1000000
