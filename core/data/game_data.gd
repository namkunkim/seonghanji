class_name GameData
extends RefCounted

## data/*.json 로더 (data-model.md §3 — 데이터가 정본이다)
##
## **문서를 파싱하지 않는다.** 문서는 「왜 그 값인가」를 말하고,
## 값 자체는 `data/*.json` 이 갖는다. 그 경계를 코드가 넘지 않는다.
##
## 순회 순서를 고정하기 위해 **Dictionary 를 직접 순회하지 않는다.**
## 정렬된 ID 배열(`region_ids` 등)을 통해서만 돈다 — dev-requirements.md §2.3.

const DATA_DIR := "res://data/"

var systems: Dictionary = {}       # SYS-xx -> Dictionary
var regions: Dictionary = {}       # RGN-xx -> Dictionary
var corridors: Dictionary = {}     # COR-xx -> Dictionary
var routes: Array[Dictionary] = []

var system_ids: Array[String] = []
var region_ids: Array[String] = []
var corridor_ids: Array[String] = []

## 성계 → 소속 권역 (정렬 고정)
var regions_of: Dictionary = {}

## 성계 → 인접 성계 (routes 에서 파생, 정렬 고정)
var neighbors: Dictionary = {}


static func load_all() -> GameData:
	var d := GameData.new()
	d._load()
	return d


func _load() -> void:
	systems = _index(_read("systems.json"))
	regions = _index(_read("regions.json"))
	corridors = _index(_read("corridors.json"))
	for r in _read("routes.json"):
		routes.append(r)

	system_ids = _sorted_keys(systems)
	region_ids = _sorted_keys(regions)
	corridor_ids = _sorted_keys(corridors)

	for sid in system_ids:
		regions_of[sid] = []
		neighbors[sid] = []
	for rid in region_ids:
		var sid: String = regions[rid]["system"]
		if regions_of.has(sid):
			regions_of[sid].append(rid)
	for rt in routes:
		var a: String = rt["connects"][0]
		var b: String = rt["connects"][1]
		if neighbors.has(a) and not neighbors[a].has(b):
			neighbors[a].append(b)
		if neighbors.has(b) and not neighbors[b].has(a):
			neighbors[b].append(a)
	for sid in system_ids:
		neighbors[sid].sort()
	build_region_adjacency()


func _read(name: String) -> Array:
	var f := FileAccess.open(DATA_DIR + name, FileAccess.READ)
	assert(f != null, "데이터를 열 수 없다: " + name)
	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Array, "배열이 아니다: " + name)
	return parsed


func _index(rows: Array) -> Dictionary:
	var d := {}
	for r in rows:
		d[r["id"]] = r
	return d


func _sorted_keys(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in d.keys():
		out.append(k)
	out.sort()
	return out


## 권역의 국력 지수. `region-power.md` §0 — 군국지 인구에서 나온 값이다.
func region_power(rid: String) -> int:
	var p = regions[rid].get("population")
	return 0 if p == null else int(p)


## 권역의 수입 지수. **국력(인구) 지수와 다르다** —
## 총합이 인구 629 대 수입 547 로 0.87 배이며, 그 13% 가 곧
## 「사람은 많으나 걷히지 않는 땅」의 표현이다 (domestic.md §4.1).
func region_income(rid: String) -> int:
	var v = regions[rid].get("income")
	return 0 if v == null else int(v)


## 권역의 생산 지수.
func region_production(rid: String) -> int:
	var v = regions[rid].get("production")
	return 0 if v == null else int(v)


## 개발여지가 몇 칸인가. 한 칸이 생산·수입 +10%p 다 (domestic.md §5.3).
const DEV_SLOTS := {"하": 1, "중": 2, "상": 3, "극상": 4}


func region_dev_slots(rid: String) -> int:
	var v = regions[rid].get("dev_potential")
	return 0 if v == null else int(DEV_SLOTS.get(String(v), 0))


func system_of(rid: String) -> String:
	return regions[rid]["system"]


func system_name(sid: String) -> String:
	return systems[sid]["name"]


## ---------------------------------------------------------------- 권역 인접
##
## **문서에 권역 간 인접표가 없다.** 성계 간 인접(star-map.md §4.5)과
## 권역별 귀속 항로(partial-occupation.md §2.1)에서 **유도한다.**
##
##   ① 같은 성계의 권역끼리는 인접
##   ② 같은 항로·관문을 귀속으로 갖는 권역끼리는 인접 (성계를 넘는 연결 9개)
##   ③ 성계는 인접한데 ②로 이어지지 않으면 **주권역끼리** 잇는다
##
## ③ 은 보완이지 정본이 아니다. 2급 성계 17개 권역은
## `partial-occupation.md` §2.2 표에 항로 열이 아예 없어 ② 로는 이을 수 없다.
## 실제 인접표가 생기면 ③ 을 버린다 — `data/_gaps.txt` 참조.
var region_adjacency: Dictionary = {}
var adjacency_fallbacks: Array[String] = []


func build_region_adjacency() -> void:
	region_adjacency.clear()
	adjacency_fallbacks.clear()
	for rid in region_ids:
		region_adjacency[rid] = []

	# ① 같은 성계
	for sid in system_ids:
		var rs: Array = regions_of[sid]
		for i in rs.size():
			for j in range(i + 1, rs.size()):
				_link(rs[i], rs[j])

	# ② 귀속 항로를 공유하는 권역
	var by_route := {}
	for rid in region_ids:
		for h in regions[rid].get("routes_hosted", []):
			if not by_route.has(h):
				by_route[h] = []
			by_route[h].append(rid)
	var route_names: Array = by_route.keys()
	route_names.sort()
	for rn in route_names:
		var group: Array = by_route[rn]
		group.sort()
		for i in group.size():
			for j in range(i + 1, group.size()):
				# **성계가 실제로 인접할 때만 잇는다.**
				# 황하 대항로처럼 여러 성계를 지나는 간선은 이름이 같아도
				# 양 끝이 서로 인접한 것은 아니다 — 태산권과 무위권이
				# 「황하항로」를 공유한다고 이웃은 아니다 (2026-08-25).
				var sa := system_of(group[i])
				var sb := system_of(group[j])
				if sa == sb or neighbors.get(sa, []).has(sb):
					_link(group[i], group[j])

	# ③ 「기저(X)」 표기 — 방향이 적혀 있다.
	#    A(성계 S)가 「기저(T)」를, B(성계 T)가 「기저(S)」를 쥐면 둘을 잇는다.
	#    양쪽이 서로를 가리켜야 한다 — 한쪽만 적힌 것은 근거가 약하다.
	var claims := {}                       # 권역 → 그 권역이 가리키는 성계 이름들
	for rid in region_ids:
		var lst: Array[String] = []
		for h in regions[rid].get("routes_hosted", []):
			var m := RegexHelper.base_targets(String(h))
			for t in m:
				lst.append(t)
		claims[rid] = lst
	for rid in region_ids:
		var sa := system_of(rid)
		for tname in claims[rid]:
			var tsid := ""
			for sid in system_ids:
				if systems[sid]["name"] == tname:
					tsid = sid
					break
			if tsid == "" or not neighbors.get(sa, []).has(tsid):
				continue
			for other in regions_of[tsid]:
				if claims[other].has(system_name(sa)):
					_link(rid, other)

	# ④ 성계는 인접한데 위로 안 이어진 경우 — 주권역끼리
	for sid in system_ids:
		for nb in neighbors[sid]:
			if not regions_of.has(nb) or sid >= nb:
				continue
			if _systems_linked(sid, nb):
				continue
			var a := _seat_of(sid)
			var b := _seat_of(nb)
			if a != "" and b != "":
				_link(a, b)
				adjacency_fallbacks.append("%s↔%s" % [systems[sid]["name"], systems[nb]["name"]])

	for rid in region_ids:
		region_adjacency[rid].sort()


func _link(a: String, b: String) -> void:
	if a == b:
		return
	if not region_adjacency[a].has(b):
		region_adjacency[a].append(b)
	if not region_adjacency[b].has(a):
		region_adjacency[b].append(a)


func _systems_linked(sa: String, sb: String) -> bool:
	for ra in regions_of[sa]:
		for rb in region_adjacency[ra]:
			if system_of(rb) == sb:
				return true
	return false


## 성계의 주권역. 없으면 첫 권역.
func _seat_of(sid: String) -> String:
	var rs: Array = regions_of[sid]
	for rid in rs:
		if regions[rid].get("is_seat") == true:
			return rid
	return rs[0] if rs.size() > 0 else ""
