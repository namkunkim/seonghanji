extends SceneTree

## 한 판을 자세히 본다. 지표가 왜 그렇게 나오는지 짚기 위한 도구다.
## 실행: godot --headless --path . --script tests/trace_campaign.gd

func _init() -> void:
	var data := GameData.load_all()
	var c := Campaign.scenario_03(data, 1000)

	print("시나리오 3 시작 배치")
	print("%-10s %5s %8s %8s %6s" % ["세력", "권역", "실효국력", "실동원", "함대"])
	print("-".repeat(44))
	for fid in c.faction_ids:
		var f: Faction = c.factions[fid]
		var fleets := 0
		for fl in c.fleets:
			if fl.owner == fid:
				fleets += 1
		print("%-10s %5d %8d %8d %6d" % [fid, f.regions.size(),
			Power.to_display(f.effective_milli(data, c.world.region_states)),
			f.mobilized(data, c.world.region_states), fleets])
	print("")

	# 분기마다 상태를 찍는다
	print("진행 (계절마다)")
	print("%6s %6s   %s" % ["틱", "연월", "세력별 권역 수"])
	print("-".repeat(70))
	var quarter := GameClock.TICKS_PER_MONTH * 3
	while not c.ended and c.world.clock.tick < Campaign.SCN03_END_TICK:
		c.step()
		if c.world.clock.tick % quarter == 0:
			var cal := c.world.clock.calendar(208)
			var parts: Array[String] = []
			for fid in c.faction_ids:
				var f: Faction = c.factions[fid]
				if f.alive:
					parts.append("%s%d" % [fid, f.regions.size()])
			print("%6d %4d.%02d   %s" % [c.world.clock.tick, cal[0], cal[1], " ".join(parts)])
	if not c.ended:
		c.ended = true
		c.end_reason = "정규 종료"

	print("")
	print("종료: %s · %d틱 · 전투 %d · 점령 %d"
		% [c.end_reason, c.world.clock.tick, c.battles, c.captures])
	print("세계 상태: %s · 최강 %s" % [c.world_state(), c.leader()])
	print("")

	var mobs := c.mobilized_all()
	print("%-10s %5s %8s %8s %6s" % ["세력", "권역", "실효국력", "실동원", "함대"])
	print("-".repeat(44))
	for fid in c.faction_ids:
		var f: Faction = c.factions[fid]
		var fleets := 0
		var ships := 0
		for fl in c.fleets:
			if fl.owner == fid:
				fleets += 1
				ships += fl.ships
		print("%-10s %5d %8d %8d %6d (%d척)" % [fid, f.regions.size(),
			Power.to_display(f.effective_milli(data, c.world.region_states)),
			mobs[fid], fleets, ships])

	# 핵심 권역이 누구 것인가 — 역사 대조
	print("")
	var watch := ["건업권", "중부권", "남부권", "태양계권", "합비권", "북부권", "성도권"]
	var by_name := {}
	for rid in data.region_ids:
		by_name[data.regions[rid]["name"]] = rid
	for nm in watch:
		var st: RegionState = c.world.region_states[by_name[nm]]
		print("  %-8s → %s" % [nm, st.owner if st.owner != "" else "중립"])
	print()
	print('AI 판단 (Operational 36회 x 세력 8 = 288 기회)')
	print('  파견        %4d' % c.dispatched)
	print('  함대 없음    %4d' % c.skip_no_idle)
	print('  방어 유보    %4d' % c.skip_defense)
	print('  목표 없음    %4d' % c.skip_no_target)
	print('  결단 보류    %4d' % c.skip_threshold)
	print()
	print('외교')
	print('  군사동맹 성립  %4d' % c.alliances_formed)
	print('  공동 방어     %4d' % c.joint_defenses)
	for k in c.diplo.tiers.keys():
		if int(c.diplo.tiers[k]) >= Diplomacy.Tier.맹약:
			print('    %s → %s (신뢰 %d)' % [k, Diplomacy.TIER_NAMES[int(c.diplo.tiers[k])], int(c.diplo.trust.get(k, 500))])
	quit(0)
