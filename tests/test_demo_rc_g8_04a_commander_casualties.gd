extends SceneTree

## DEMO-RC-G8-04a — 장수 부상·전사·포로, 지휘 승계, 명령 혼선, 총사령관 상실 승패.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const Victory := preload("res://core/demo_red_cliffs/red_cliffs_victory_resolver.gd")
const Commander := preload("res://core/demo_red_cliffs/red_cliffs_commander_resolver.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")

var passed := 0
var failed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; print("  x %s" % label)


func _init() -> void:
	var loaded := Setup.load_default(); check(loaded.ok, "default setup loads")
	_test_flagship_and_vice(loaded.setup)
	_test_damage_bands_and_vice_succession(loaded.setup)
	_test_destroyed_branch(loaded.setup)
	_test_rescue_equipment(loaded.setup)
	_test_surrender_and_level_succession(loaded.setup)
	_test_leaderless(loaded.setup)
	_test_failed_retreat(loaded.setup)
	_test_victory_supreme(loaded.setup)
	_test_pipeline(loaded.setup)
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed else Harness.EXIT_PASS)


func _fixture(setup: Dictionary) -> Dictionary:
	var battle := Battle.new(); battle.initialize(setup)
	var resolver := Commander.new(); var init: Dictionary = resolver.initialize(setup)
	return {"resolver": resolver, "init": init, "state": resolver.initial_state(),
		"effects": battle._state.combat_effect_state.duplicate(true), "nav": battle._state.live_navigation.duplicate(true)}


func _mark(effects: Dictionary, squadron_id: String, damage_state: String, morale_status := "steady") -> void:
	var row: Dictionary = effects.squadrons[squadron_id]; row.damage_state = damage_state; row.morale_status = morale_status
	var operational := damage_state != "destroyed" and morale_status != "surrendered"
	row.capabilities = {"operational": operational, "can_command": operational, "can_attack": operational and morale_status != "retreating",
		"can_change_mission": operational and morale_status != "retreating", "forced_retreat": operational and morale_status == "retreating", "surrendered": morale_status == "surrendered"}


func _place(nav: Dictionary, squadron_id: String, position: Array) -> void: nav[squadron_id] = {"position": position, "facing_deg": 0.0}


func _test_flagship_and_vice(setup: Dictionary) -> void:
	var liu_squad: Dictionary = {}; var zhuge: Dictionary = {}
	for squad in setup.squadrons:
		if squad.id == "RC-LIU-SQ-01": liu_squad = squad
		if squad.id == "RC-LIU-SQ-02": zhuge = squad
	check(bool(liu_squad.flagship) and not bool(zhuge.flagship), "Liu fleet flagship is Liu Bei's own squadron (SQ-01), not Zhuge Liang's")
	var draft := Draft.new(setup)
	var normalized: Dictionary = draft.draft_snapshot()
	var fleet: Dictionary = normalized.fleet_groups.filter(func(f): return f.id == "RC-LIU-FLT-01")[0]
	check(fleet.flagship_squadron_id == "RC-LIU-SQ-01", "auto flagship rule ranks the faction supreme commander's squadron first despite lower command")
	var fx := _fixture(setup); check(fx.init.ok, "commander resolver initializes")
	var state: Dictionary = fx.state
	check(state.officers["CHR-0107"].role == "vice_commander" and state.officers["CHR-0107"].squadron_id == "RC-LIU-SQ-01", "Guan Yu rides Liu Bei's flagship as vice commander")
	check(state.officers["CHR-0033"].squadron_id == "RC-CAO-SQ-01" and state.officers["CHR-0186"].squadron_id == "RC-SUN-SQ-01", "Cao Ren and Lu Su ride their fleet flagships")
	check(state.fleets["RC-LIU-FLT-01"].commander_id == "CHR-0128", "Liu fleet commander is Liu Bei")
	var supremes: Dictionary = fx.resolver.supreme_commanders(state)
	check(supremes.liu_bei.officer_id == "CHR-0128" and supremes.cao_cao.officer_id == "CHR-0034" and not supremes.liu_bei.lost and not supremes.cao_cao.lost, "supreme commanders map to roster ids and start unharmed")
	var bad := setup.duplicate(true); bad.fleet_groups[0]["vice_commander"] = {"id": "CHR-0134", "name": "제갈량"}
	check(not Setup.validate_document(bad).ok, "a squadron commander cannot double as vice commander")


func _test_damage_bands_and_vice_succession(setup: Dictionary) -> void:
	var fx := _fixture(setup); var effects: Dictionary = fx.effects
	_mark(effects, "RC-LIU-SQ-02", "moderate_damage"); _mark(effects, "RC-LIU-SQ-01", "heavy_damage")
	var result: Dictionary = fx.resolver.resolve(fx.state, effects, [], {}, fx.nav, 3)
	check(result.ok, "damage band turn resolves")
	var state: Dictionary = result.state
	check(state.officers["CHR-0134"].status == "light_injury" and state.officers["CHR-0134"].cause == "moderate_damage", "moderate damage gives the squadron commander a light injury")
	check(state.officers["CHR-0128"].status == "severe_injury", "heavy damage gives the squadron commander a severe injury")
	check(state.officers["CHR-0107"].status == "unhurt", "damage-band injuries do not touch the vice commander")
	var fleet: Dictionary = state.fleets["RC-LIU-FLT-01"]
	check(fleet.commander_id == "CHR-0107" and fleet.flagship_squadron_id == "RC-LIU-SQ-01" and fleet.confusion_turns == [4], "vice commander succeeds first, flagship unchanged, confusion next turn only")
	check(result.events.filter(func(e): return e.event_type == "fleet_command_succeeded").size() == 1, "one succession event")
	var next_overrides: Dictionary = fx.resolver.command_overrides(state, 4)
	check(next_overrides["RC-LIU-SQ-01"].extra_tiers == 2 and next_overrides["RC-LIU-SQ-02"].extra_tiers == 2 and next_overrides["RC-LIU-SQ-01"].command == 95,
		"confusion adds two penalty tiers to every fleet squadron and the flagship limit uses Guan Yu's command")
	var later: Dictionary = fx.resolver.command_overrides(state, 5)
	check(later["RC-LIU-SQ-01"].extra_tiers == 0 and later["RC-LIU-SQ-01"].command == 95 and not later.has("RC-LIU-SQ-02"), "confusion lasts exactly one turn")
	check(fx.resolver.command_overrides(state, 3).get("RC-LIU-SQ-02", {}).get("extra_tiers", 0) == 0, "confusion never applies retroactively to the succession turn")
	var draft := Draft.new(setup)
	var base: Dictionary = draft.squadron_metrics("RC-LIU-SQ-02")
	draft.set_command_overrides(next_overrides)
	var confused: Dictionary = draft.squadron_metrics("RC-LIU-SQ-02")
	check(int(confused.penalty_tier) == mini(int(base.penalty_tier) + 2, 4) and int(confused.mobility_percent) == -5 * int(confused.penalty_tier), "confusion stacks with command-limit tiers up to the cap")
	# 악화 방향으로만 바뀐다.
	_mark(effects, "RC-LIU-SQ-01", "moderate_damage")
	var again: Dictionary = fx.resolver.resolve(state, effects, [], {}, fx.nav, 4)
	check(again.state.officers["CHR-0128"].status == "severe_injury" and again.events.is_empty(), "a lower band never heals or re-triggers")


func _test_destroyed_branch(setup: Dictionary) -> void:
	# 연쇄 폭발: 조조 기함과 동승한 조인이 함께 전사한다.
	var fx := _fixture(setup); var effects: Dictionary = fx.effects
	_mark(effects, "RC-CAO-SQ-01", "destroyed")
	var chain := [{"event_type": "chain_effects_applied", "turn": 6, "target_squadron_id": "RC-CAO-SQ-01"}]
	var killed: Dictionary = fx.resolver.resolve(fx.state, effects, chain, {}, fx.nav, 6)
	check(killed.state.officers["CHR-0034"].status == "killed" and killed.state.officers["CHR-0033"].status == "killed", "chain-explosion destruction kills commander and vice aboard")
	check(killed.supreme_commanders.cao_cao.lost and killed.state.fleets["RC-CAO-FLT-01"].leaderless, "Cao Cao lost; single-squadron fleet with dead vice is leaderless")
	# 적만 반경 안 → 포로.
	var fx2 := _fixture(setup); _mark(fx2.effects, "RC-CAO-SQ-01", "destroyed")
	_place(fx2.nav, "RC-CAO-SQ-01", [800.0, 400.0]); _place(fx2.nav, "RC-SUN-SQ-01", [900.0, 400.0])
	var captured: Dictionary = fx2.resolver.resolve(fx2.state, fx2.effects, [], {}, fx2.nav, 6)
	check(captured.state.officers["CHR-0034"].status == "captured" and captured.state.officers["CHR-0034"].cause == "destroyed_enemy_nearby", "enemy within 120 and no friend: captured")
	# 적이 정확히 반경 경계 밖 → 생환.
	var fx3 := _fixture(setup); _mark(fx3.effects, "RC-CAO-SQ-01", "destroyed")
	_place(fx3.nav, "RC-CAO-SQ-01", [800.0, 400.0]); _place(fx3.nav, "RC-SUN-SQ-01", [921.0, 400.0])
	var escaped: Dictionary = fx3.resolver.resolve(fx3.state, fx3.effects, [], {}, fx3.nav, 6)
	check(escaped.state.officers["CHR-0034"].status == "severe_injury" and escaped.state.officers["CHR-0034"].cause == "destroyed_recovered", "no enemy within 120: recovered with severe injury")
	# 아군이 적과 같은 거리 → 아군 우선.
	var fx4 := _fixture(setup); _mark(fx4.effects, "RC-LIU-SQ-02", "destroyed")
	_place(fx4.nav, "RC-LIU-SQ-02", [800.0, 400.0]); _place(fx4.nav, "RC-CAO-SQ-01", [880.0, 400.0]); _place(fx4.nav, "RC-LIU-SQ-01", [720.0, 400.0])
	var tie: Dictionary = fx4.resolver.resolve(fx4.state, fx4.effects, [], {}, fx4.nav, 6)
	check(tie.state.officers["CHR-0134"].status == "severe_injury", "friend at equal distance to the nearest enemy wins the tie")
	# 아군이 적보다 멀면 포로. 작전 불능 아군은 구조하지 못한다.
	var fx5 := _fixture(setup); _mark(fx5.effects, "RC-LIU-SQ-02", "destroyed")
	_place(fx5.nav, "RC-LIU-SQ-02", [800.0, 400.0]); _place(fx5.nav, "RC-CAO-SQ-01", [850.0, 400.0]); _place(fx5.nav, "RC-LIU-SQ-01", [700.0, 400.0])
	check(fx5.resolver.resolve(fx5.state, fx5.effects, [], {}, fx5.nav, 6).state.officers["CHR-0134"].status == "captured", "friend farther than the nearest enemy: captured")
	var fx6 := _fixture(setup); _mark(fx6.effects, "RC-LIU-SQ-02", "destroyed"); _mark(fx6.effects, "RC-LIU-SQ-01", "operational", "surrendered")
	_place(fx6.nav, "RC-LIU-SQ-02", [800.0, 400.0]); _place(fx6.nav, "RC-CAO-SQ-01", [850.0, 400.0]); _place(fx6.nav, "RC-LIU-SQ-01", [800.0, 410.0])
	check(fx6.resolver.resolve(fx6.state, fx6.effects, [], {}, fx6.nav, 6).state.officers["CHR-0134"].status == "captured", "a surrendered friend cannot recover a commander")
	var drifting := {"squadrons": {"RC-CAO-SQ-01": {"status": "drifting"}}}
	var fx7 := _fixture(setup); _mark(fx7.effects, "RC-LIU-SQ-02", "destroyed")
	_place(fx7.nav, "RC-LIU-SQ-02", [800.0, 400.0]); _place(fx7.nav, "RC-CAO-SQ-01", [850.0, 400.0])
	check(fx7.resolver.resolve(fx7.state, fx7.effects, [], drifting, fx7.nav, 6).state.officers["CHR-0134"].status == "severe_injury", "a drifting enemy cannot capture")


func _test_rescue_equipment(setup: Dictionary) -> void:
	var rescue_setup := setup.duplicate(true)
	for squad in rescue_setup.squadrons:
		if squad.id == "RC-LIU-FC-01": squad.composition[0].mission_equipment_id = "FAST-EQ-RESCUE"
	check(Setup.validate_document(rescue_setup).ok, "rescue-equipped fast craft setup validates")
	var fx := _fixture(rescue_setup); check(fx.init.ok, "rescue fixture initializes")
	_mark(fx.effects, "RC-LIU-SQ-02", "destroyed")
	_place(fx.nav, "RC-LIU-SQ-02", [800.0, 400.0]); _place(fx.nav, "RC-CAO-SQ-01", [810.0, 400.0]); _place(fx.nav, "RC-LIU-FC-01", [900.0, 400.0])
	check(fx.resolver.resolve(fx.state, fx.effects, [], {}, fx.nav, 6).state.officers["CHR-0134"].status == "severe_injury", "rescue-equipped friend within radius recovers even when the enemy is closer")
	_place(fx.nav, "RC-LIU-FC-01", [921.0, 400.0])
	check(fx.resolver.resolve(fx.state, fx.effects, [], {}, fx.nav, 6).state.officers["CHR-0134"].status == "captured", "rescue equipment outside the radius does not help")


func _test_surrender_and_level_succession(setup: Dictionary) -> void:
	var fx := _fixture(setup); _mark(fx.effects, "RC-LIU-SQ-01", "moderate_damage", "surrendered")
	var result: Dictionary = fx.resolver.resolve(fx.state, fx.effects, [], {}, fx.nav, 5)
	check(result.state.officers["CHR-0128"].status == "captured" and result.state.officers["CHR-0107"].status == "captured", "surrender captures commander and vice aboard (surrender outranks damage band)")
	var fleet: Dictionary = result.state.fleets["RC-LIU-FLT-01"]
	check(fleet.commander_id == "CHR-0134" and fleet.flagship_squadron_id == "RC-LIU-SQ-02" and fleet.confusion_turns == [6], "with the vice gone, the remaining squadron commander succeeds and his squadron becomes flagship")
	check(result.supreme_commanders.liu_bei.lost, "Liu Bei captured marks the alliance supreme commander lost")
	var captured_fc := {"squadrons": {"RC-LIU-FC-01": {"status": "captured"}}}
	var fx2 := _fixture(setup)
	check(fx2.resolver.resolve(fx2.state, fx2.effects, [], captured_fc, fx2.nav, 5).state.officers["CHR-0136"].status == "captured", "a captured drifting fast craft takes its commander prisoner")


func _test_leaderless(setup: Dictionary) -> void:
	var fx := _fixture(setup); _mark(fx.effects, "RC-SUN-SQ-01", "heavy_damage")
	var first: Dictionary = fx.resolver.resolve(fx.state, fx.effects, [], {}, fx.nav, 2)
	check(first.state.fleets["RC-SUN-FLT-01"].commander_id == "CHR-0186", "Zhou Yu severely injured: Lu Su succeeds in a single-squadron fleet")
	_mark(fx.effects, "RC-SUN-SQ-01", "destroyed")
	_place(fx.nav, "RC-SUN-SQ-01", [800.0, 400.0]); _place(fx.nav, "RC-CAO-SQ-01", [850.0, 400.0])
	var second: Dictionary = fx.resolver.resolve(first.state, fx.effects, [], {}, fx.nav, 3)
	check(second.state.officers["CHR-0186"].status == "captured" and second.state.officers["CHR-0211"].status == "captured", "flagship destroyed near the enemy: both aboard captured (severe upgrades to captured)")
	check(second.state.fleets["RC-SUN-FLT-01"].leaderless, "no successor left: fleet is leaderless")
	check(fx.resolver.command_overrides(second.state, 9).get("RC-SUN-SQ-01", {}).get("extra_tiers", 0) == 2, "leaderless confusion persists every turn")
	var view: Dictionary = fx.resolver.visible("cao_cao", second.state)
	check(view.officers.all(func(o): return o.faction_id == "cao_cao" or ["killed", "captured"].has(o.status)) and view.officers.any(func(o): return o.officer_id == "CHR-0211"), "enemies see only terminal outcomes of the other side")
	check(fx.resolver.visible("liu_bei", second.state).officers.any(func(o): return o.officer_id == "CHR-0186" and o.viewer_state == "own"), "Liu Bei sees allied Sun Quan officers")


func _test_failed_retreat(setup: Dictionary) -> void:
	var points := {"cao_cao": {"position": [1600, 300], "arrival_radius": 60}, "liu_sun_alliance": {"position": [0, 650], "arrival_radius": 60}}
	var fx := _fixture(setup); _mark(fx.effects, "RC-CAO-SQ-01", "heavy_damage", "retreating")
	var concluded: Dictionary = fx.resolver.conclude(fx.state, fx.effects, fx.nav, "liu_sun_alliance", points, 9)
	check(concluded.ok and concluded.state.officers["CHR-0034"].status == "captured" and concluded.state.officers["CHR-0034"].cause == "failed_retreat", "retreat unfinished when the enemy wins: captured")
	check(not fx.resolver.conclude(concluded.state, fx.effects, fx.nav, "liu_sun_alliance", points, 9).ok, "conclusion runs once")
	check(fx.resolver.conclude(fx.state, fx.effects, fx.nav, "cao_cao", points, 9).state.officers["CHR-0034"].status == "unhurt", "retreating side that wins is not captured")
	_place(fx.nav, "RC-CAO-SQ-01", [1600.0, 340.0])
	check(fx.resolver.conclude(fx.state, fx.effects, fx.nav, "liu_sun_alliance", points, 9).state.officers["CHR-0034"].status == "unhurt", "inside own escape point: retreat succeeded")


func _row(remaining: int) -> Dictionary: return {"original_cost": 100, "remaining_cost": remaining, "squadron_count": 1, "surrendered_squadron_count": 0}
func _inputs(liu_lost: bool, cao_lost: bool) -> Dictionary:
	return {"turn": 5, "factions": {"liu_bei": _row(100), "sun_quan": _row(100), "cao_cao": _row(100)},
		"flagships": {"liu_bei": {"destroyed": false}, "cao_cao": {"destroyed": false}}, "escapes": {"cao_cao": false, "liu_sun_alliance": false},
		"supreme_commanders": {"liu_bei": {"lost": liu_lost}, "cao_cao": {"lost": cao_lost}}}


func _test_victory_supreme(_setup: Dictionary) -> void:
	var resolver := Victory.new(); check(resolver.initialize().ok, "victory resolver initializes")
	var liu: Dictionary = resolver.evaluate(_inputs(true, false))
	check(liu.winner_faction_id == "cao_cao" and liu.reason_codes == ["liu_bei_supreme_commander_lost"], "Liu Bei killed/captured defeats the alliance")
	var cao: Dictionary = resolver.evaluate(_inputs(false, true))
	check(cao.winner_faction_id == "liu_sun_alliance" and cao.reason_codes == ["cao_cao_supreme_commander_lost"] and cao.victory_type == "decisive", "Cao Cao killed/captured is a decisive alliance victory")
	var both: Dictionary = resolver.evaluate(_inputs(true, true))
	check(both.winner_faction_id == "cao_cao" and both.reason_codes == ["simultaneous_terminal_conditions_cao_priority"], "simultaneous supreme losses keep Cao priority")
	var none: Dictionary = resolver.evaluate(_inputs(false, false))
	check(none.ok and not none.winner_present, "no supreme loss, no winner")


func _test_pipeline(setup: Dictionary) -> void:
	var battle := Battle.new(); check(battle.initialize(setup).ok, "pipeline battle initializes")
	check(battle.commander_state().officers.size() == 8, "pipeline tracks 5 squadron commanders plus 3 vice commanders")
	check(battle.submit_command_draft().ok and battle.submit_sun_control_choice("no", true).ok, "turn 1 orders submit")
	var cao_row: Dictionary = battle._state.combat_effect_state.squadrons["RC-CAO-SQ-01"]
	cao_row.hull_points = int(cao_row.maximum_hull_points) * 3000 / 10000; cao_row.damage_state = "heavy_damage"
	var receipt: Dictionary = battle.resolve_turn()
	check(receipt.ok and battle.phase() == "victory_check", "Cao Cao severe injury does not end the battle")
	var changed: Array = receipt.commander_events.filter(func(e): return e.event_type == "commander_status_changed" and e.officer_id == "CHR-0034")
	check(changed.size() == 1 and changed[0].status == "severe_injury", "receipt carries Cao Cao's severe injury")
	check(battle.commander_state().fleets["RC-CAO-FLT-01"].commander_id == "CHR-0033", "Cao Ren takes command through the real pipeline")
	var before: Dictionary = Draft.new(setup).squadron_metrics("RC-CAO-SQ-01")
	var confused: Dictionary = battle.viewer_command_penalty_metrics("cao_cao", "RC-CAO-SQ-01")
	check(int(confused.penalty_tier) == mini(4, int(before.penalty_tier) + 2), "next-turn command penalty preview includes command confusion (Cao Ren's command, +2 tiers)")
	check(not battle.commander_report().ok, "commander report stays hidden until the battle concludes")

	var liu := Battle.new(); check(liu.initialize(setup).ok, "Liu surrender fixture initializes")
	check(liu.submit_command_draft().ok and liu.submit_sun_control_choice("no", true).ok, "Liu fixture orders submit")
	var liu_row: Dictionary = liu._state.combat_effect_state.squadrons["RC-LIU-SQ-01"]
	liu_row.morale_basis_points = 0; liu_row.morale_status = "surrendered"; liu_row.capabilities.operational = false; liu_row.capabilities.surrendered = true
	var liu_receipt: Dictionary = liu.resolve_turn()
	check(liu_receipt.ok and liu.phase() == "battle_concluded" and liu_receipt.victory_result.reason_codes == ["liu_bei_supreme_commander_lost"], "Liu Bei's flagship surrendering ends the battle as an alliance defeat")
	var report: Dictionary = liu.commander_report()
	check(report.ok and report.factions.liu_bei.captured.any(func(o): return o.officer_id == "CHR-0128") and report.factions.liu_bei.captured.any(func(o): return o.officer_id == "CHR-0107"), "results report lists Liu Bei and Guan Yu as captured")
	check(report.factions.cao_cao.survived.size() == 2, "results report lists unharmed Cao Cao and Cao Ren as survived")
