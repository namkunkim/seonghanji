extends SceneTree

## 예산 검산 — 코드 재계산 대 문서값 (domestic.md §4.4)
##
## 실행: godot --headless --path . --script tests/verify_budget.gd
##
## **이것은 합격/불합격 시험이 아니라 대조표다.** 어긋남 자체가 산출물이다.
## `verify_power.gd` 가 V-29(국력 요약표 3세력 불일치)를 잡아낸 것과 같은 방식이며,
## 같은 이유로 만든다 — **문서와 코드가 각자 계산하면 언젠가 갈라진다.**

## domestic.md §4.4 잠정 예산표. 문서를 손으로 옮긴 값이다.
const DOC := {
	"조조":     {"income": 18130, "admin": 12210, "left": 5152},
	"유장":     {"income":  5035, "admin":   520, "left": 4131},
	"손권":     {"income":  3995, "admin":   936, "left": 2717},
	"유종":     {"income":  2975, "admin":   666, "left": 2112},
	"사섭":     {"income":  1425, "admin":   312, "left": 1062},
	"공손강":   {"income":   855, "admin":   168, "left":  656},
	"마등한수": {"income":   875, "admin":   276, "left":  558},
	"장로":     {"income":   810, "admin":   288, "left":  471},
}

const ORDER: Array[String] = [
	"조조", "유장", "손권", "유종", "사섭", "공손강", "마등한수", "장로",
]

## 문서표의 함대비는 **실동원 전부를 균형 편성으로 채웠을 때**의 값이다.
## 캠페인 초기 함대는 실동원 ÷ 10 개뿐이라 그대로 비교할 수 없다 —
## 여기서는 문서와 같은 전제로 다시 세운다.
const DOC_FLEET := {
	"조조": 768, "유장": 384, "손권": 342, "유종": 197,
	"사섭": 51, "공손강": 31, "마등한수": 41, "장로": 51,
}


func _init() -> void:
	var d := GameData.load_all()
	var c := Campaign.scenario_03(d, 1)

	print("")
	print("전대당 유지점 — 편성안 6종 (ship-specs.md §7.2)")
	var plans: Array = Economy.PLANS.keys()
	plans.sort()
	for p in plans:
		print("  %-10s 유지점 %.3f · 유지비 %.1f" % [
			p, Economy.plan_point_milli(p) / 1000.0,
			Economy.plan_upkeep_milli(p) / 1000.0])
	print("")

	print("%-9s %8s %8s   %8s %8s   %8s %8s" % [
		"세력", "수입", "문서", "행정비", "문서", "잔여", "문서"])
	print("-".repeat(66))

	var bad := 0
	for fid in ORDER:
		var f: Faction = c.factions[fid]
		var inc := Economy.faction_income(d, c.world.region_states, f.regions)
		var adm := Economy.faction_admin(d, c.world.region_states, f.regions,
			f.governance)
		var flt: int = DOC_FLEET[fid]
		var left := inc - adm - flt
		var doc: Dictionary = DOC[fid]
		var mark := ""
		if inc != int(doc["income"]) or adm != int(doc["admin"]) \
				or absi(left - int(doc["left"])) > 1:
			mark = "  ★"
			bad += 1
		print("%-9s %8d %8d   %8d %8d   %8d %8d%s" % [
			fid, inc, int(doc["income"]), adm, int(doc["admin"]),
			left, int(doc["left"]), mark])

	print("-".repeat(66))
	print("")

	# 실동원 → 전대 수 (combat.md §4.3.3)
	#
	# **M0 결손 ④ 는 2026-08-25 에 닫혔다 (V-36·V-37).**
	# 문서 §3.4-c 의 손 계산이 폐기되고 인접표 유도가 정본이 되었다.
	# 이 표는 두 경로가 다시 갈라지지 않는지 지키는 자리다.
	print("실동원 — 산식 대 문서 (V-37 이후 정본 일치)")
	print("  %-8s %6s %6s   %6s %6s   %s" % [
		"세력", "국력", "산식", "동원율", "문서", "전대"])
	var docrate := {"조조": 0.48, "유장": 0.59, "손권": 0.71, "유종": 0.64}
	for fid in ["조조", "손권", "유종", "유장"]:
		var f: Faction = c.factions[fid]
		var eff := f.effective_milli(d, c.world.region_states) / 1000
		var mob := f.mobilized(d, c.world.region_states, c.world.graph, 0)
		var rate := float(mob) / float(maxi(eff, 1))
		var sq := Economy.squadrons_milli(mob) / 1000.0
		var want := int(round(float(eff) * float(docrate[fid])))
		var mark := "" if absi(mob - want) <= 2 else "  * 어긋남 %+d" % (mob - want)
		print("  %-8s %6d %6d   %6.2f %6.2f   %5.1f전대%s" % [
			fid, eff, mob, rate, float(docrate[fid]), sq, mark])
	print("")

	# 항별 분해 — 어느 항이 모자란가
	print("동원율 항별 분해 (region-power.md §3.4-b)")
	for fid in ["조조", "손권", "유종", "유장"]:
		var f: Faction = c.factions[fid]
		var bd := f.count_borders(d)
		var nt := Power.newly_taken_burden_milli(c.world.region_states, f.regions, 0)
		var hp := f.expedition_hops(d, c.world.graph)
		print("  %-8s 개방%2d 회랑%2d → −%3d · 신복속 −%3d · 원정 %d홉 −%3d · 통치 %+d = %.3f" % [
			fid, bd[0], bd[1], bd[0] * 30 + bd[1] * 5, nt,
			hp, Power.expedition_burden_milli(hp),
			Power.governance_milli(f.governance),
			Power.mobilization_full_milli(bd[0], bd[1], nt, hp, f.governance,
				f.wandering) / 1000.0])
	print("")

	# 위임의 대가 — 실동원이 얼마나 줄어드는가
	var cao: Faction = c.factions["조조"]
	var before := cao.mobilized(d, c.world.region_states, c.world.graph, 0)
	var b0 := Economy.balance(d, c.world.region_states, cao.regions,
		cao.governance, 0)
	for rid in cao.regions:
		c.world.region_states[rid].delegated = true
	var after := cao.mobilized(d, c.world.region_states, c.world.graph, 0)
	var b1 := Economy.balance(d, c.world.region_states, cao.regions,
		cao.governance, 0)
	print("위임의 대가 — 조조가 전 권역을 위임하면 (domestic.md §3)")
	print("  실동원  %d → %d" % [before, after])
	print("  수입    %d → %d" % [b0[0], b1[0]])
	print("  행정비  %d → %d" % [b0[1], b1[1]])
	print("  잔여    %d → %d  (%+d)" % [b0[3], b1[3], b1[3] - b0[3]])
	print("")
	print("  재정은 편해지고 적벽에는 가지 못한다.")
	print("")

	if bad == 0:
		print("문서와 어긋나는 세력 없음")
	else:
		print("★ 어긋나는 세력 %d" % bad)
	quit(1 if bad > 0 else 0)
