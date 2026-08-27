class_name Roster
extends RefCounted

## 인물 로스터 — 세력이 쥔 사람들 (character-assignments.md · generals-stats.md)
##
## 2026-08-25 신설. 그때까지 **코어가 인물을 한 명도 읽지 않았다** —
## `characters.json` 492인에 5스탯이 다 들어 있고 `assignments.json` 이
## 시나리오별 배치를 갖고 있는데, **모든 함대가 통솔 50 으로 싸우고 있었다.**
## 주유도 하후돈도 없었다.
##
## **이번 세션에 여섯 번째로 만난 같은 패턴이다** —
## 회랑 넷 · 훈련도 · 기술 · 천명 · 패권 압력 · 그리고 인물.
## **문서에 있는데 코드가 안 읽는다.**

## ---------------------------------------------------------------- 세력 이름
##
## 배치표는 시대 진영 이름을 쓰고(위·오·유표 진영), 캠페인은 군주 이름을 쓴다
## (조조·손권·유종). **두 이름 체계를 여기서 잇는다.**
const FACTION_ALIAS := {
	"위": "조조",
	"오": "손권",
	"유표 진영": "유종",
	"유장·익주 진영": "유장",
	"서량 진영": "마등한수",
}

## **「군웅」은 한 덩어리가 아니다.** 장로·공손강·사섭이 각자 독립 세력이며
## (`character-assignments.md` §0 「독자 세력 지속형 — 흡수 없음」),
## 배치표는 그들을 같은 라벨로 묶어 두었다. 이름으로 되돌린다.
const WARLORD_SELF: Array[String] = ["장로", "공손강", "사섭"]

## 시나리오 3 에서 캠페인 세력에 배정하지 않는 진영.
##
## ⚠ **「원소 진영」은 208 년에도 라벨이 남아 있다.**
## `character-assignments.md` §0 이 「붕괴 **207** · **219 부터** 위에 흡수」로 정해
## **그 사이 12년이 라벨만 남는다** — 208 배치에 원소·안량·문추가 「소속」으로 나온다.
## 문서의 단순화이지 오류가 아니므로 데이터를 고치지 않고 **여기서 거른다.**
##
## 「촉」은 유비 세력이고 시나리오 3 에서 유랑이라 캠페인에 없다.
const UNMAPPED: Array[String] = ["원소 진영", "촉", "기타 군웅(명장)"]


## 시나리오의 세력별 인물 목록. 세력 → Array[Dictionary]
##
## **각 목록은 통솔 내림차순으로 정렬한다** — 순회 순서가 결정론의 전제이고
## (dev-requirements.md §2.3), 임명은 위에서부터 채운다 (`ship-specs.md` §6.6).
static func build(data: GameData, scenario: String) -> Dictionary:
	var out := {}
	for a in data.assignments:
		if String(a.get("scenario", "")) != scenario:
			continue
		if String(a.get("status", "")) != "소속":
			continue
		var raw := String(a.get("faction", ""))
		if raw == "" or UNMAPPED.has(raw):
			continue
		var c: Dictionary = data.characters.get(String(a["character"]), {})
		if c.is_empty():
			continue
		var fid := String(FACTION_ALIAS.get(raw, raw))
		if raw == "군웅":
			# 독자 세력 지속형 — 인물 이름이 곧 세력 이름인 경우만 잡는다
			var nm := String(c.get("name", ""))
			if not WARLORD_SELF.has(nm):
				continue
			fid = nm
		if not out.has(fid):
			out[fid] = []
		out[fid].append(c)
	for fid in out.keys():
		out[fid].sort_custom(_by_command)
	return out


## 통솔 내림차순. 같으면 ID 순 — **동점에서 순서가 흔들리면 결정론이 깨진다.**
static func _by_command(a: Dictionary, b: Dictionary) -> bool:
	var ca := stat_of(a, "통솔")
	var cb := stat_of(b, "통솔")
	if ca != cb:
		return ca > cb
	return String(a.get("id", "")) < String(b.get("id", ""))


static func stat_of(c: Dictionary, key: String) -> int:
	var s = c.get("stats")
	if s == null:
		return 50                                # 「보정 없음」 (generals-stats.md §0.1)
	return int(s.get(key, 50))


## ---------------------------------------------------------------- 지휘 한도
##
## `ship-specs.md` §6.1. 통솔이 **한 제독이 운용할 수 있는 유지점 총합**을 정한다.
## 구간 하한 → 한도
const COMMAND_LIMIT: Array = [
	[95, 30], [85, 24], [75, 18], [65, 12], [55, 8], [40, 5], [0, 2],
]


static func command_limit(command: int) -> int:
	for b in COMMAND_LIMIT:
		if command >= int(b[0]):
			return int(b[1])
	return 2


## 그 세력이 지휘할 수 있는 유지점 총합. **병력이 곧 전력이 아니다 —
## 지휘할 사람이 있어야 전력이 된다** (§6.2).
##
## 상위 `n` 인만 센다. 나머지는 내정 담당관과 임무대장으로 간다 (§6.7).
static func command_capacity(roster: Array, n: int) -> int:
	var cap := 0
	for i in mini(n, roster.size()):
		cap += command_limit(stat_of(roster[i], "통솔"))
	return cap
