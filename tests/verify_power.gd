extends SceneTree

## 국력 검산 — 데이터 재계산 대 문서값 (region-power.md §3.2 · scenario-setup.md §4.2)
##
## 실행: godot --headless --path . --script tests/verify_power.gd
##
## **이것은 합격/불합격 시험이 아니라 대조표다.** 어긋남 자체가 산출물이다.
##
## ⚠ 시나리오 3 배치를 여기 적어 두었다. 원래는 `data/` 에 있어야 한다 —
## `world-states.json`(시작 배치 21) 추출이 아직이라 임시로 둔다.

const HOLDINGS := {
	"조조": {
		"systems": ["사예", "예주", "연주", "청주", "서주", "기주", "유주", "병주", "남양", "회남"],
		"regions": ["북부권"], "doc": 212, "mob": 0.35,
	},
	"유장": {"systems": [], "regions": ["성도권", "재동권", "파군권"], "doc": 62, "mob": 0.60},
	"손권": {"systems": [], "regions": ["건업권", "오회권", "예장권"], "doc": 44, "mob": 0.75},
	"유종": {"systems": [], "regions": ["중부권", "남부권", "태양계권"], "doc": 31, "mob": 0.60},
	"장로": {"systems": [], "regions": ["남정권", "상용권"], "doc": 11, "mob": 0.0},
	"사섭": {"systems": [], "regions": ["교지권", "남해권"], "doc": 12, "mob": 0.0},
	"공손강": {"systems": [], "regions": ["양평권", "대방권"], "doc": 7, "mob": 0.0},
	"마등·한수": {"systems": ["옹주", "양주"], "regions": [], "doc": 9, "mob": 0.0},
	"중립": {"systems": [], "regions": ["익주군권", "월수권"], "doc": 12, "mob": 0.0},
}

const ORDER := ["조조", "유장", "손권", "유종", "장로", "사섭", "공손강", "마등·한수", "중립"]


func _init() -> void:
	var data := GameData.load_all()

	var by_name := {}
	for rid in data.region_ids:
		by_name[data.regions[rid]["name"]] = rid
	var sys_by_name := {}
	for sid in data.system_ids:
		sys_by_name[data.systems[sid]["name"]] = sid

	print("시나리오 3 (208) 국력 검산 — 데이터 재계산 대 문서값")
	print("")
	print("%-10s %6s %6s %8s   %6s %6s" % ["세력", "권역", "재계산", "문서", "실동원", "문서"])
	print("%s" % "-".repeat(56))

	var total_regions := 0
	var mismatch: Array[String] = []
	for name in ORDER:
		var h: Dictionary = HOLDINGS[name]
		var rids: Array = []
		for sname in h["systems"]:
			var sid = sys_by_name.get(sname)
			if sid == null:
				print("  ! 성계를 찾을 수 없다: ", sname)
				continue
			for rid in data.regions_of[sid]:
				rids.append(rid)
		for rname in h["regions"]:
			var rid = by_name.get(rname)
			if rid == null:
				print("  ! 권역을 찾을 수 없다: ", rname)
				continue
			rids.append(rid)

		var milli := Power.total_effective_milli(data, rids)
		var eff := Power.to_display(milli)
		var doc: int = h["doc"]
		var mob_txt := "—"
		var docmob_txt := "—"
		if h["mob"] > 0.0:
			mob_txt = str(Power.mobilized(milli, h["mob"]))
			docmob_txt = str(int(round(float(doc) * h["mob"])))
		var flag := ""
		if doc > 0 and absi(eff - doc) * 100 > doc * 5:      # 편차 5% 초과
			flag = "  ← 어긋남"
			mismatch.append("%s %d/%d" % [name, eff, doc])
		print("%-10s %6d %6d %8s   %6s %6s%s"
			% [name, rids.size(), eff, str(doc) if doc > 0 else "—",
			   mob_txt, docmob_txt, flag])
		total_regions += rids.size()

	print("%s" % "-".repeat(56))
	print("권역 합계 %d (정본 45)" % total_regions)
	print("")

	# 적벽 성립 판정 — 문서는 조조 67 대 손유 37 = 1.81배
	var cc := _milli(data, by_name, sys_by_name, "조조")
	var sq := _milli(data, by_name, sys_by_name, "손권")
	var cao := Power.mobilized(cc, 0.35)
	var sun := Power.mobilized(sq, 0.75)
	var liu := 15                                        # 유비 유랑 특례 (§3.4-c)
	print("적벽 성립 판정")
	print("  재계산: 조조 %d 대 손유 동맹 %d = %.2f배" % [cao, sun + liu, float(cao) / float(sun + liu)])
	print("  문서값: 조조 74 대 손유 동맹 48 = 1.54배  (2026-08-24 재산출, V-29)")
	print("")
	if mismatch.is_empty():
		print("문서와 어긋나는 세력 없음")
	else:
		print("문서와 어긋나는 세력 %d: %s" % [mismatch.size(), ", ".join(mismatch)])
	quit(0)


func _milli(data: GameData, by_name: Dictionary, sys_by_name: Dictionary, name: String) -> int:
	var h: Dictionary = HOLDINGS[name]
	var rids: Array = []
	for sname in h["systems"]:
		for rid in data.regions_of[sys_by_name[sname]]:
			rids.append(rid)
	for rname in h["regions"]:
		rids.append(by_name[rname])
	return Power.total_effective_milli(data, rids)
