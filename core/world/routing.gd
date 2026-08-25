class_name Routing
extends RefCounted

## 항로망 경로 탐색 (star-map.md §4.5 · time-and-monetization.md §3.1)
##
## ## 간선 소요는 배율로 떨어진다
##
##     소요(틱) = 45 × 배율
##
## 고속항로 ×1 = 45분 · 중회랑 ×3 = 135분 · 대회랑 ×5 = 225분 · 기저 항로 ×4 = 180분.
## **문서 소요표(§3.1)를 그대로 재현한다.** 별도 표를 두지 않는다.
##
## ## 결정론
##
## 최단 경로가 여럿일 때 어느 것을 고르느냐가 결과를 바꾼다.
## **동률은 성계 ID 순으로 깬다** — 우선순위 선택을 (비용, ID) 정렬로 고정한다.
## 노드가 20개 남짓이라 힙 없이 선형 탐색으로 충분하고, 그쪽이 순서가 더 분명하다.
##
## ⚠ **회랑은 어떤 수단으로도 배율이 1이 되지 않는다** (불가침 §2-2).
## 경로 비용에 회랑 할인이 들어갈 자리를 만들지 않는다 —
## 유일한 예외인 영거 운하는 `corridors.json` 의 `canal` 로 다루며, 여기서 처리하지 않는다.

## 고속항로 1구간. 모든 소요의 기준 단위다.
const BASE_LEG_TICKS: int = 45

const UNREACHABLE: int = -1


## 인접 리스트를 만든다. `{성계: [{to, ticks, kind, corridor}]}`
## **간선 순서를 고정한다** — 목적지 ID 순으로 정렬한다.
static func build_graph(data: GameData) -> Dictionary:
	var g := {}
	for rt in data.routes:
		var a: String = rt["connects"][0]
		var b: String = rt["connects"][1]
		var mult: float = rt["multiplier"] if rt["multiplier"] != null else 4.0
		var ticks := int(round(float(BASE_LEG_TICKS) * mult))
		for pair in [[a, b], [b, a]]:
			if not g.has(pair[0]):
				g[pair[0]] = []
			g[pair[0]].append({
				"to": pair[1], "ticks": ticks,
				"kind": rt["kind"], "corridor": rt["corridor"],
			})
	for k in g.keys():
		g[k].sort_custom(func(x, y):
			if x["ticks"] != y["ticks"]:
				return x["ticks"] < y["ticks"]
			return x["to"] < y["to"])
	return g


## 최단 소요(틱). 닿지 않으면 UNREACHABLE.
static func travel_ticks(graph: Dictionary, from_sys: String, to_sys: String) -> int:
	if from_sys == to_sys:
		return 0
	var costs := _dijkstra(graph, from_sys)
	return costs[0].get(to_sys, UNREACHABLE)


## 경로. 출발지를 포함하고 목적지로 끝난다. 닿지 않으면 빈 배열.
static func path(graph: Dictionary, from_sys: String, to_sys: String) -> Array[String]:
	var out: Array[String] = []
	if from_sys == to_sys:
		out.append(from_sys)
		return out
	var r := _dijkstra(graph, from_sys)
	var prev: Dictionary = r[1]
	if not prev.has(to_sys):
		return out
	var cur := to_sys
	while cur != from_sys:
		out.append(cur)
		cur = prev[cur]
	out.append(from_sys)
	out.reverse()
	return out


## 경로가 지나는 회랑 목록. 「봉쇄가 성립한다」를 판정하는 입력이다.
static func corridors_on_path(graph: Dictionary, p: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for i in range(p.size() - 1):
		for e in graph.get(p[i], []):
			if e["to"] == p[i + 1]:
				if e["corridor"] != null and not out.has(e["corridor"]):
					out.append(e["corridor"])
				break
	return out


## 다익스트라. 반환 [비용, 직전노드].
##
## 동률을 ID 순으로 깬다 — 같은 비용의 노드가 여럿일 때 어느 것을 먼저 펴느냐가
## 경로 선택을 바꾸므로, 순서를 고정하지 않으면 결정론이 깨진다.
static func _dijkstra(graph: Dictionary, src: String) -> Array:
	var dist := {src: 0}
	var prev := {}
	var done := {}
	while true:
		var cur := ""
		var best := -1
		var keys: Array = dist.keys()
		keys.sort()                                  # 순회 순서 고정
		for k in keys:
			if done.has(k):
				continue
			if best < 0 or dist[k] < best:
				best = dist[k]
				cur = k
		if cur == "":
			break
		done[cur] = true
		for e in graph.get(cur, []):
			var nd: int = best + int(e["ticks"])
			var to: String = e["to"]
			if not dist.has(to) or nd < dist[to]:
				dist[to] = nd
				prev[to] = cur
	return [dist, prev]
