class_name Strategy
extends RefCounted

## 전략 AI (ai-design.md §3 · §5)
##
## ## 설계 원칙 셋을 코드가 지킨다 (§1)
##
##   1. **최적화가 아니라 성격** — 같은 판에서 세력마다 다른 답을 낸다
##   2. **치팅 금지** — AI 도 플레이어와 같은 정보·같은 규칙을 쓴다
##   3. **디버깅 가능성** — 왜 그 수를 골랐는지 점수 내역이 남는다
##
## ## 주기 (§2)
##
## | 계층 | 결정 대상 | 주기 |
## |---|---|---|
## | **Grand** | 세력 목표 · 노선 · 외교 | 게임 내 계절 = **180틱** |
## | **Operational** | 권역 목표 · 함대 배치 · 개발 | 게임 내 월 = **60틱** |
## | Tactical | 전투 페이즈 · 계략 | 전투 시 (S3) |
##
## **결정 빈도가 낮은 것이 성능상 큰 이점이다.** 항행에 45분~3시간 45분이
## 걸리므로 AI 는 매 틱 사고할 필요가 없다.

const GRAND_PERIOD_TICKS: int = 180        # 게임 내 계절
const OPERATIONAL_PERIOD_TICKS: int = 60   # 게임 내 월


## ---------------------------------------------------------------- 절단 가치
##
## §5.2 — **이 문서에서 가장 중요한 부분이다.**
##
## > 한 권역만 빼앗아 적의 나머지를 비지로 만들 수 있다.
## > AI 가 이것을 발견하지 못하면 부분 점령은 플레이어 전용 기술이 된다.
##
## 절단점을 찾고, 그것을 제거했을 때 고립되는 권역의 국력 합을 가치로 삼는다.
## **여몽의 백의도강이 「설계된 이벤트」가 아니라 「AI 가 발견한 최적수」가 된다.**


## 그 세력이 보유한 권역들의 절단점. {권역ID: 절단 가치}
## 순회를 정렬된 배열로만 한다 — 결정론 (§2.3)
static func cut_values(data: GameData, owned: Array) -> Dictionary:
	var nodes := owned.duplicate()
	nodes.sort()
	if nodes.size() < 3:
		return {}                       # 둘 이하면 절단점이 의미 없다

	var index := {}
	for i in nodes.size():
		index[nodes[i]] = i

	var adj: Array = []
	for i in nodes.size():
		adj.append([])
	for i in nodes.size():
		for nb in data.region_adjacency.get(nodes[i], []):
			if index.has(nb):
				adj[i].append(int(index[nb]))
	for i in nodes.size():
		adj[i].sort()

	var out := {}
	for i in nodes.size():
		var isolated := _isolated_if_removed(adj, i)
		if isolated.is_empty():
			continue
		var value := 0
		for j in isolated:
			value += data.region_power(nodes[j])
		out[nodes[i]] = value
	return out


## i 를 빼면 어느 노드들이 본체에서 떨어지는가.
## 본체는 **남은 노드 중 가장 큰 덩어리**로 본다.
## 동률이면 첫 노드 번호가 작은 쪽 — 순서를 고정해야 결정론이 선다.
static func _isolated_if_removed(adj: Array, skip: int) -> Array:
	var n := adj.size()
	var seen := {}
	var comps: Array = []
	for s in n:
		if s == skip or seen.has(s):
			continue
		var comp: Array = []
		var stack: Array = [s]
		seen[s] = true
		while not stack.is_empty():
			var u: int = stack.pop_back()
			comp.append(u)
			for v in adj[u]:
				if v == skip or seen.has(v):
					continue
				seen[v] = true
				stack.append(v)
		comp.sort()
		comps.append(comp)
	if comps.size() <= 1:
		return []
	var main := 0
	for i in comps.size():
		if comps[i].size() > comps[main].size():
			main = i
		elif comps[i].size() == comps[main].size() and comps[i][0] < comps[main][0]:
			main = i
	var out: Array = []
	for i in comps.size():
		if i != main:
			for v in comps[i]:
				out.append(v)
	out.sort()
	return out


## ---------------------------------------------------------------- 권역 가치
##
## §5.1  권역 가치 = 국력 + 항로 + 절단 + 연결 + 상징 − 방어 비용

const W_ROUTE_PER_HOST: int = 3
const W_CORRIDOR_HOST: int = 5
const W_CONNECT: int = 4
const W_SYMBOL_EARTH: int = 20             # 태양계권 — 국력 최소, 명분 최대
const W_DEFENSE_PER_BORDER: int = 2


static func region_value(data: GameData, rid: String,
		own_regions: Array, cut_value: int = 0) -> Dictionary:
	var r: Dictionary = data.regions[rid]
	var power := data.region_power(rid)

	var route := 0
	for h in r.get("routes_hosted", []):
		# **이름이 아니라 정본 목록으로 판정한다** (2026-08-25) —
		# 진령삼도·이릉협도(대회랑)·기산도·남중산도가 이름 필터를 빠져나가
		# AI 가 회랑 넷을 개방 항로로 보고 있었다.
		route += W_CORRIDOR_HOST if data.is_corridor(String(h)) else W_ROUTE_PER_HOST

	var connect := 0
	var borders := 0
	for nb in data.region_adjacency.get(rid, []):
		if own_regions.has(nb):
			connect += W_CONNECT
		else:
			borders += 1

	var symbol := W_SYMBOL_EARTH if r["name"] == "태양계권" else 0
	var defense := borders * W_DEFENSE_PER_BORDER
	var total := power + route + cut_value + connect + symbol - defense

	# **왜 그 수를 골랐는지 남긴다** (§1.4 디버깅 가능성)
	return {
		"region": rid, "total": total,
		"power": power, "route": route, "cut": cut_value,
		"connect": connect, "symbol": symbol, "defense": -defense,
	}


## 공격 목표를 고른다. 점수 최대. 동률은 권역 ID 순.
## 인접하지 않은 곳은 노리지 않는다 — 통과 강제 (star-map.md §3.3 ①)
static func pick_target(data: GameData, targets: Array, own: Array,
		cuts: Dictionary = {}) -> Dictionary:
	var sorted_targets := targets.duplicate()
	sorted_targets.sort()
	var best := {}
	for rid in sorted_targets:
		var reachable := false
		for nb in data.region_adjacency.get(rid, []):
			if own.has(nb):
				reachable = true
				break
		if not reachable:
			continue
		var v := region_value(data, rid, own, int(cuts.get(rid, 0)))
		if best.is_empty() or v["total"] > best["total"]:
			best = v
	return best


## ---------------------------------------------------------------- 자기 방어
##
## §5.4 — **같은 연산을 자기 영토에 적용해 자신의 절단점을 방어한다.**
##
## | 절단점의 성격 | 방어 부담 |
## |---|---|
## | 회랑·관문 귀속 | **대폭 감소** — 소수로 대군을 막는다 |
## | 기저 항로만 | 전면 방어 필요 |

const DEFENSE_FLEETS_CORRIDOR: int = 1
const DEFENSE_FLEETS_OPEN: int = 2


## 그 세력이 남겨야 할 방어 함대 수.
## 자기 절단점을 세되, 회랑을 낀 곳은 싸게 친다.
static func defense_need(data: GameData, own: Array) -> int:
	var cuts := cut_values(data, own)
	if cuts.is_empty():
		return DEFENSE_FLEETS_CORRIDOR
	var need := 0
	var keys: Array = cuts.keys()
	keys.sort()
	for rid in keys:
		need += DEFENSE_FLEETS_CORRIDOR if _is_choke(data, rid) else DEFENSE_FLEETS_OPEN
	return need


static func _is_choke(data: GameData, rid: String) -> bool:
	for h in data.regions[rid].get("routes_hosted", []):
		if data.is_corridor(String(h)):
			return true
	return false


## ---------------------------------------------------------------- 결단 임계
##
## §4.1 — **원소의 약점은 우둔함이 아니라 구조다.**
##
## > if (최고 점수 − 차선 점수) < 결단 임계:  결정 보류
##
## 강한 세력이기에 선택지가 많고, 명문형이기에 임계가 높다.
## **AI 가 실수하는 것이 아니라 원소답게 행동하는 것이다.**
##
## ⚠ 문서가 값을 준 것은 **명문형 0.8** 하나뿐이다.
##
## **나머지는 M0 실측으로 정했다** (2026-08-25). 처음 잡은 잠정값
## (명사 0.6 · 인덕 0.5 · 실리 0.35 · 패도 0.25 · 무단 0.15)에서는
## **결단 보류가 288회 중 278회(96.5%)**로 아무도 움직이지 않았다.
##
## 임계는 **최고와 차선의 상대 격차**에 걸린다. 인접 권역들의 점수는
## 대체로 비슷하므로 25% 격차조차 드물다. 명문형만 문서값으로 두고
## 나머지를 크게 낮췄다 — **유장(명문형)만 못 움직이는 것이 설계 의도**다.
const DECISION_THRESHOLD := {
	"명문형": 800,      # 문서값 0.8 — 원소·유장. 「원소의 약점은 구조다」
	"명사형": 250,      # 실측 조정
	"인덕형": 150,      # 실측 조정
	"실리형": 100,      # 실측 조정
	"패도형": 50,       # 조조는 빨리 결단한다
	"무단형": 20,       # 동탁·여포는 재지 않는다
}


static func decision_threshold_milli(lord_type: String) -> int:
	return int(DECISION_THRESHOLD.get(lord_type, 350))


## 최고와 차선의 상대 격차가 임계에 못 미치면 보류한다.
## **보류하는 사이에 상황이 변한다** — 그것이 원소의 재현이다.
static func decides(best_total: int, second_total: int, lord_type: String) -> bool:
	if best_total <= 0:
		return false
	if second_total <= 0:
		return true
	var gap_milli := (best_total - second_total) * 1000 / best_total
	return gap_milli >= decision_threshold_milli(lord_type)


## 상위 둘을 함께 돌려준다. 결단 임계 판정에 차선이 필요하기 때문이다.
static func rank_targets(data: GameData, targets: Array, own: Array,
		cuts: Dictionary = {}) -> Array:
	var sorted_targets := targets.duplicate()
	sorted_targets.sort()
	var scored: Array = []
	for rid in sorted_targets:
		var reachable := false
		for nb in data.region_adjacency.get(rid, []):
			if own.has(nb):
				reachable = true
				break
		if not reachable:
			continue
		scored.append(region_value(data, rid, own, int(cuts.get(rid, 0))))
	# 점수 내림차순, 동률은 권역 ID 순 — 결정론
	scored.sort_custom(func(a, b):
		if a["total"] != b["total"]:
			return a["total"] > b["total"]
		return a["region"] < b["region"])
	return scored


## ---------------------------------------------------------------- 역사 편향
##
## §6.2 — **역사가 자연스럽게 재현되되, 강제되지 않아야 한다.**
##
##     if (해당 세력이 역사상 이 이벤트의 주체였다):
##         utility × (1 + HB)
##
## | 모드 | HB | 성격 |
## |---|---|---|
## | 역사 중시 | 0.5 | 역사대로 흐르기 쉽다. 입문자용 |
## | **표준** | **0.25** | 역사 경향은 있되 자주 이탈 |
## | 자유 역사 | 0.0 | 순수 유틸리티. 완전한 역사 생성 |
##
## ## HB 만으로는 부족하다
##
## HB 는 **가중치**다. 점수 최대값을 그대로 고르면 시드가 달라도 같은 판이 나온다 —
## 실제로 M0 1차에서 100회가 전부 같은 결과였다 (`m0-report.md` §2.1).
##
## §11.1 의 목표 「**40~60% — 절반은 역사대로, 절반은 이탈**」이 성립하려면
## **선택 자체가 확률적**이어야 한다. HB 가 저울을 기울이고, 확률이 흔든다.

const HB_HISTORICAL_MILLI: int = 500      # 역사 중시
const HB_STANDARD_MILLI: int = 250        # 표준
const HB_FREE_MILLI: int = 0              # 자유 역사

## 확률 선택에 올릴 후보 수. 너무 넓히면 AI 가 엉뚱한 수를 둔다.
const CANDIDATE_POOL: int = 3


## 시나리오별 역사적 목표. 「그 세력이 역사상 그리로 갔는가」다.
##
## SCN-03 적벽 전야 — `scenario-setup.md` §4 · `star-map.md` §6.1
const HISTORICAL_TARGETS := {
	"SCN-03": {
		"조조": ["중부권", "남부권", "건업권"],      # 형주 남하 → 강동
		"손권": ["합비권", "중부권"],                # 오의 북상은 합비를 지난다
		"유종": [],                                  # 항복한 쪽이라 진공 목표가 없다
		"유장": ["남정권"],                          # 한중 장로와의 대치
		"장로": ["재동권"],                          # 익주 방면
		"마등한수": ["장안권"],                      # 관중
		"사섭": [],
		"공손강": [],
	},
}


static func is_historical(scenario: String, faction: String, rid_name: String) -> bool:
	var byfac: Dictionary = HISTORICAL_TARGETS.get(scenario, {})
	var lst: Array = byfac.get(faction, [])
	return lst.has(rid_name)


## 역사 편향을 반영한 점수. 음수 점수에는 걸지 않는다 —
## 역사적 목표라고 해서 **나쁜 수가 좋아지지는 않는다.**
static func biased_total(data: GameData, entry: Dictionary,
		scenario: String, faction: String, hb_milli: int) -> int:
	var t: int = int(entry["total"])
	if t <= 0 or hb_milli <= 0:
		return t
	var nm: String = data.regions[entry["region"]]["name"]
	if not is_historical(scenario, faction, nm):
		return t
	return t * (1000 + hb_milli) / 1000


## **확률적 목표 선정.** 상위 후보를 점수에 비례해 뽑는다.
##
## 최고점을 그냥 고르지 않는 이유는 §11.1 이 「절반은 이탈」을 요구하기 때문이다.
## 후보를 셋으로 좁혀 두어 **엉뚱한 수는 두지 않는다.**
##
## 동률과 순회 순서가 결정론을 깨지 않도록 후보는 이미 정렬된 배열로 받는다.
static func choose_weighted(ranked: Array, rng: RngStream,
		data: GameData, scenario: String, faction: String,
		hb_milli: int) -> Dictionary:
	if ranked.is_empty():
		return {}
	var pool: Array = []
	var weights: Array[int] = []
	var sum := 0
	for i in mini(CANDIDATE_POOL, ranked.size()):
		var w := biased_total(data, ranked[i], scenario, faction, hb_milli)
		if w <= 0:
			continue
		pool.append(ranked[i])
		weights.append(w)
		sum += w
	if pool.is_empty():
		return ranked[0]
	var roll := rng.below(sum)
	var acc := 0
	for i in pool.size():
		acc += weights[i]
		if roll < acc:
			var out: Dictionary = pool[i].duplicate()
			out["biased"] = weights[i]
			out["historical"] = is_historical(
				scenario, faction, data.regions[out["region"]]["name"])
			return out
	return pool[pool.size() - 1]
