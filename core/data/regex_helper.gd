class_name RegexHelper
extends RefCounted

## 「기저(병주)」 · 「기저(기주·청주)」 같은 표기에서 성계 이름을 뽑는다.
##
## `partial-occupation.md` §2 의 「접속 항로·관문」 열이 기저 항로를
## **방향과 함께** 적는다 — 그것을 권역 인접 유도에 쓴다 (game_data.gd).
static func base_targets(entry: String) -> Array[String]:
	var out: Array[String] = []
	var e := entry.strip_edges()
	if not e.begins_with("기저"):
		return out
	var lp := e.find("(")
	var rp := e.rfind(")")
	if lp < 0 or rp <= lp:
		return out
	for part in e.substr(lp + 1, rp - lp - 1).split("·"):
		var t := part.strip_edges()
		if t != "":
			out.append(t)
	return out
