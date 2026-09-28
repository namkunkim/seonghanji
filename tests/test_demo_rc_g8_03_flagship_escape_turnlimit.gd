extends SceneTree

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const Victory := preload("res://core/demo_red_cliffs/red_cliffs_victory_resolver.gd")

var passed := 0
var failed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; print("  x %s" % label)


func _init() -> void:
	var resolver := Victory.new(); check(resolver.initialize().ok, "victory resolver initializes")
	check(resolver.rules_snapshot().escape_points.cao_cao.position == [1600.0, 300.0], "cao escape point loads from rules")
	check(resolver.rules_snapshot().escape_points.liu_sun_alliance.position == [0.0, 650.0], "alliance escape point loads from rules")
	_test_flagship_conditions(resolver)
	_test_escape_conditions(resolver)
	_test_reason_priority(resolver)
	_test_turn_limit_comparison(resolver)
	_test_escape_status_helper()
	_test_turn_boundary_flagship_wiring()
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed else Harness.EXIT_PASS)


func _row(remaining: int, squadron_count := 1, surrendered := 0) -> Dictionary:
	return {"original_cost": 100, "remaining_cost": remaining, "squadron_count": squadron_count, "surrendered_squadron_count": surrendered}


func _inputs(turn: int, liu_flagship_destroyed: bool, cao_flagship_destroyed: bool, cao_escaped: bool, alliance_escaped: bool,
		liu_remaining := 100, sun_remaining := 100, cao_remaining := 100) -> Dictionary:
	return {"turn": turn, "factions": {"liu_bei": _row(liu_remaining), "sun_quan": _row(sun_remaining), "cao_cao": _row(cao_remaining)},
		"flagships": {"liu_bei": {"destroyed": liu_flagship_destroyed}, "cao_cao": {"destroyed": cao_flagship_destroyed}},
		"escapes": {"cao_cao": cao_escaped, "liu_sun_alliance": alliance_escaped}}


func _test_flagship_conditions(resolver) -> void:
	var liu_destroyed: Dictionary = resolver.evaluate(_inputs(4, true, false, false, false))
	check(liu_destroyed.ok and liu_destroyed.winner_faction_id == "cao_cao" and liu_destroyed.reason_codes == ["liu_bei_flagship_destroyed"] and liu_destroyed.victory_type == "decisive",
		"Liu Bei flagship destroyed alone defeats the alliance even with cost/morale untouched")
	# Cao Cao's flagship falling wins for the alliance regardless of Cao Cao's
	# own remaining cost/morale (here Cao is otherwise untouched at 100%).
	var cao_destroyed: Dictionary = resolver.evaluate(_inputs(4, false, true, false, false))
	check(cao_destroyed.ok and cao_destroyed.winner_faction_id == "liu_sun_alliance" and cao_destroyed.reason_codes == ["cao_cao_flagship_destroyed"] and cao_destroyed.victory_type == "decisive",
		"Cao Cao flagship destroyed alone wins for the alliance regardless of Cao Cao's own remaining forces")


func _test_escape_conditions(resolver) -> void:
	var cao_escaped: Dictionary = resolver.evaluate(_inputs(4, false, false, true, false))
	check(cao_escaped.ok and cao_escaped.winner_faction_id == "liu_sun_alliance" and cao_escaped.reason_codes == ["cao_cao_flagship_escaped"] and cao_escaped.victory_type == "decisive",
		"Cao Cao flagship reaching Cao Cao's own escape point wins for the alliance")
	var alliance_escaped: Dictionary = resolver.evaluate(_inputs(4, false, false, false, true))
	check(alliance_escaped.ok and alliance_escaped.winner_faction_id == "liu_sun_alliance" and alliance_escaped.reason_codes == ["alliance_escape_limited_victory"] and alliance_escaped.victory_type == "limited",
		"Liu Bei flagship and required squadrons reaching the alliance escape point is a LIMITED alliance victory")
	# When Cao Cao is already decisively defeated on its own cost, reaching the
	# alliance escape point the same turn must not downgrade the result to
	# "limited" — the stronger decisive condition takes priority.
	var decisive_over_limited: Dictionary = resolver.evaluate(_inputs(4, false, false, false, true, 100, 100, 20))
	check(decisive_over_limited.ok and decisive_over_limited.winner_faction_id == "liu_sun_alliance" \
		and decisive_over_limited.reason_codes == ["cao_cao_terminal_condition"] and decisive_over_limited.victory_type == "decisive",
		"a decisive Cao Cao defeat takes priority over a simultaneous limited alliance escape")


func _test_reason_priority(resolver) -> void:
	# Liu Bei's own 70%bp cost loss AND flagship destruction both true: the
	# flagship reason is the more specific/decisive one and takes priority.
	var liu_both: Dictionary = resolver.evaluate(_inputs(4, true, false, false, false, 20))
	check(liu_both.ok and liu_both.reason_codes == ["liu_bei_flagship_destroyed"], "Liu Bei flagship reason takes priority over Liu Bei's own cost-loss reason")
	# Cao Cao's flagship destroyed AND escaped both true: flagship destruction
	# is the more specific reason.
	var cao_both: Dictionary = resolver.evaluate(_inputs(4, false, true, true, false))
	check(cao_both.ok and cao_both.reason_codes == ["cao_cao_flagship_destroyed"], "Cao Cao flagship-destroyed reason takes priority over flagship-escaped reason")
	# Both sides' flagships fall on the same resolved turn: Cao Cao priority
	# from G8-01/02 still applies unchanged.
	var simultaneous: Dictionary = resolver.evaluate(_inputs(4, true, true, false, false))
	check(simultaneous.ok and simultaneous.winner_faction_id == "cao_cao" and simultaneous.reason_codes == ["simultaneous_terminal_conditions_cao_priority"],
		"both flagships destroyed the same turn still yields to Cao Cao simultaneous priority")


func _test_turn_limit_comparison(resolver) -> void:
	# Turn 19: nothing else fired, and the turn-limit branch must not fire early.
	var not_yet: Dictionary = resolver.evaluate(_inputs(19, false, false, false, false, 100, 100, 40))
	check(not_yet.ok and not not_yet.winner_present, "turn-limit comparison does not fire before the configured turn_limit")
	# Turn 20, alliance combined ratio (100%) higher than Cao's (40%).
	var alliance_higher: Dictionary = resolver.evaluate(_inputs(20, false, false, false, false, 100, 100, 40))
	check(alliance_higher.ok and alliance_higher.winner_faction_id == "liu_sun_alliance" and alliance_higher.reason_codes == ["turn_limit_alliance_cost_ratio_higher"],
		"turn 20 with a higher alliance cost ratio gives the alliance a decisive win")
	# Turn 20, Cao's ratio (100%) higher than the alliance's combined (60%: 120/200).
	var cao_higher: Dictionary = resolver.evaluate(_inputs(20, false, false, false, false, 100, 20, 100))
	check(cao_higher.ok and cao_higher.winner_faction_id == "cao_cao" and cao_higher.reason_codes == ["turn_limit_cao_cost_ratio_higher"],
		"turn 20 with a higher Cao cost ratio gives Cao a decisive win")
	# Turn 20, exact tie (both 100%): Cao wins the tie-break.
	var tie: Dictionary = resolver.evaluate(_inputs(20, false, false, false, false))
	check(tie.ok and tie.winner_faction_id == "cao_cao" and tie.reason_codes == ["turn_limit_tie_cao_priority"], "turn 20 exact tie favors Cao Cao")
	# Turn 20, but a stronger condition (combined alliance 70%bp loss, with
	# neither member individually over threshold) already fires this turn: the
	# turn-limit fallback must not override it.
	var stronger_condition_first: Dictionary = resolver.evaluate(_inputs(20, false, false, false, false, 40, 0, 100))
	check(stronger_condition_first.ok and stronger_condition_first.winner_faction_id == "cao_cao" and stronger_condition_first.reason_codes == ["alliance_combined_loss_threshold"],
		"a same-turn combined-loss defeat is resolved before the turn-limit fallback is ever consulted")


func _test_escape_status_helper() -> void:
	var loaded := Setup.load_default(); check(loaded.ok, "default setup loads")
	var battle := Battle.new(); check(battle.initialize(loaded.setup).ok, "battle initializes for helper access")
	var rules: Dictionary = battle._victory_resolver.rules_snapshot()
	var squadrons: Dictionary = battle._state.combat_effect_state.squadrons

	var arrived: Dictionary = battle._state.live_navigation.duplicate(true)
	arrived["RC-CAO-SQ-01"] = {"position": [1600.0, 300.0], "facing_deg": 0.0}
	check(battle._escape_status(rules, battle._state.applied_setup, squadrons, arrived).cao_cao, "Cao flagship exactly at its escape point is detected as arrived")

	var just_outside: Dictionary = battle._state.live_navigation.duplicate(true)
	just_outside["RC-CAO-SQ-01"] = {"position": [1600.0, 361.0], "facing_deg": 0.0}
	check(not battle._escape_status(rules, battle._state.applied_setup, squadrons, just_outside).cao_cao, "Cao flagship one unit past the arrival radius is not arrived")

	var both_arrived: Dictionary = battle._state.live_navigation.duplicate(true)
	both_arrived["RC-LIU-SQ-01"] = {"position": [0.0, 650.0], "facing_deg": 0.0}
	both_arrived["RC-LIU-SQ-02"] = {"position": [0.0, 650.0], "facing_deg": 0.0}
	check(battle._escape_status(rules, battle._state.applied_setup, squadrons, both_arrived).liu_sun_alliance,
		"alliance escape requires the flagship's whole fleet; both members arrived succeeds")

	var only_flagship: Dictionary = battle._state.live_navigation.duplicate(true)
	only_flagship["RC-LIU-SQ-02"] = {"position": [0.0, 650.0], "facing_deg": 0.0}
	check(not battle._escape_status(rules, battle._state.applied_setup, squadrons, only_flagship).liu_sun_alliance,
		"alliance escape fails when the flagship's fleet-mate has not also arrived")

	var fleetmate_destroyed_squadrons: Dictionary = squadrons.duplicate(true)
	fleetmate_destroyed_squadrons["RC-LIU-SQ-01"] = squadrons["RC-LIU-SQ-01"].duplicate(true)
	fleetmate_destroyed_squadrons["RC-LIU-SQ-01"].capabilities = squadrons["RC-LIU-SQ-01"].capabilities.duplicate(true)
	fleetmate_destroyed_squadrons["RC-LIU-SQ-01"].capabilities.operational = false
	check(not battle._escape_status(rules, battle._state.applied_setup, fleetmate_destroyed_squadrons, both_arrived).liu_sun_alliance,
		"a non-operational (destroyed/surrendered) required squadron never counts as arrived even at the exact position")


func _test_turn_boundary_flagship_wiring() -> void:
	# End-to-end through the real resolve_turn() pipeline: mutating the
	# authoritative combat_effect_state (same technique G8-01's own turn-boundary
	# test uses) proves red_cliffs_combat_effects.victory_inputs() correctly
	# resolves the flagship squadron id from applied_setup, not just that the
	# pure resolver logic is correct in isolation.
	var loaded := Setup.load_default(); check(loaded.ok, "default setup loads")
	var liu_flagship_down := Battle.new(); check(liu_flagship_down.initialize(loaded.setup).ok, "Liu flagship fixture initializes")
	check(liu_flagship_down.submit_command_draft().ok, "Liu flagship fixture Liu order submits")
	check(liu_flagship_down.submit_sun_control_choice("no", true).ok, "Liu flagship fixture Sun AI choice submits")
	var liu_flagship_row: Dictionary = liu_flagship_down._state.combat_effect_state.squadrons["RC-LIU-SQ-02"]
	liu_flagship_row.current_composition = []; liu_flagship_row.hull_points = 0; liu_flagship_row.damage_state = "destroyed"; liu_flagship_row.capabilities.operational = false
	var liu_flagship_receipt: Dictionary = liu_flagship_down.resolve_turn()
	check(liu_flagship_receipt.ok and liu_flagship_receipt.victory_result.winner_faction_id == "cao_cao" \
		and liu_flagship_receipt.victory_result.reason_codes == ["liu_bei_flagship_destroyed"] and liu_flagship_down.phase() == "battle_concluded",
		"destroying Liu Bei's actual flagship squadron (RC-LIU-SQ-02) concludes the battle through the real pipeline")

	var cao_flagship_down := Battle.new(); check(cao_flagship_down.initialize(loaded.setup).ok, "Cao flagship fixture initializes")
	check(cao_flagship_down.submit_command_draft().ok, "Cao flagship fixture Liu order submits")
	check(cao_flagship_down.submit_sun_control_choice("no", true).ok, "Cao flagship fixture Sun AI choice submits")
	var cao_flagship_row: Dictionary = cao_flagship_down._state.combat_effect_state.squadrons["RC-CAO-SQ-01"]
	cao_flagship_row.current_composition = []; cao_flagship_row.hull_points = 0; cao_flagship_row.damage_state = "destroyed"; cao_flagship_row.capabilities.operational = false
	var cao_flagship_receipt: Dictionary = cao_flagship_down.resolve_turn()
	check(cao_flagship_receipt.ok and cao_flagship_receipt.victory_result.winner_faction_id == "liu_sun_alliance" \
		and cao_flagship_receipt.victory_result.reason_codes == ["cao_cao_flagship_destroyed"] and cao_flagship_down.phase() == "battle_concluded",
		"destroying Cao Cao's actual flagship squadron (RC-CAO-SQ-01) concludes the battle through the real pipeline regardless of Cao's other forces")
