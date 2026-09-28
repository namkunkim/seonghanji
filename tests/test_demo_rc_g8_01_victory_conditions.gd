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
	_test_deterministic_conditions(resolver)
	_test_turn_boundary_integration()
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed else Harness.EXIT_PASS)


func _inputs(liu_remaining: int, sun_remaining: int, cao_remaining: int, liu_surrendered := 0, sun_surrendered := 0, cao_surrendered := 0) -> Dictionary:
	return {"turn": 4, "factions": {
		"liu_bei": {"original_cost": 100, "remaining_cost": liu_remaining, "squadron_count": 2, "surrendered_squadron_count": liu_surrendered},
		"sun_quan": {"original_cost": 100, "remaining_cost": sun_remaining, "squadron_count": 1, "surrendered_squadron_count": sun_surrendered},
		"cao_cao": {"original_cost": 100, "remaining_cost": cao_remaining, "squadron_count": 1, "surrendered_squadron_count": cao_surrendered}}}


func _test_deterministic_conditions(resolver) -> void:
	var normal: Dictionary = resolver.evaluate(_inputs(100, 100, 100))
	check(normal.ok and not normal.winner_present and normal.future_conditions_pending == ["flagship", "escape", "turn_limit"], "no basic terminal condition remains pending")
	var liu_loss: Dictionary = resolver.evaluate(_inputs(30, 100, 100))
	check(liu_loss.ok and liu_loss.winner_faction_id == "cao_cao" and liu_loss.reason_codes == ["liu_bei_terminal_condition"], "Liu 70-percent cost loss gives Cao victory")
	var sun_only: Dictionary = resolver.evaluate(_inputs(100, 30, 100))
	check(sun_only.ok and not sun_only.winner_present, "Sun-only defeat does not end the Liu-led alliance")
	var cao_loss: Dictionary = resolver.evaluate(_inputs(100, 100, 30))
	check(cao_loss.ok and cao_loss.winner_faction_id == "liu_sun_alliance", "Cao 70-percent cost loss gives alliance victory")
	var simultaneous: Dictionary = resolver.evaluate(_inputs(30, 100, 30))
	check(simultaneous.ok and simultaneous.winner_faction_id == "cao_cao" and simultaneous.reason_codes == ["simultaneous_terminal_conditions_cao_priority"], "simultaneous terminal conditions give Cao priority")
	var morale: Dictionary = resolver.evaluate(_inputs(100, 100, 100, 2))
	check(morale.ok and morale.winner_faction_id == "cao_cao", "all Liu squadrons surrendered gives Cao victory")
	var invalid: Dictionary = resolver.evaluate(_inputs(101, 100, 100))
	check(not invalid.ok, "invalid cost input rejects")


func _test_turn_boundary_integration() -> void:
	var loaded := Setup.load_default(); check(loaded.ok, "default setup loads")
	var battle := Battle.new(); check(battle.initialize(loaded.setup).ok, "battle initializes victory resolver")
	var first: Dictionary = battle.submit_command_draft(); check(first.ok, "Liu orders submit")
	check(battle.submit_sun_control_choice("no", true).ok, "Sun AI choice submits")
	var receipt: Dictionary = battle.resolve_turn()
	check(receipt.ok and receipt.has("victory_result") and not receipt.victory_result.winner_present, "resolved receipt contains no-winner basic evaluation")
	check(battle.phase() == "victory_check" and battle.continue_turn().ok and battle.turn() == 2, "no-winner result alone permits next turn")
	var forced := Battle.new(); check(forced.initialize(loaded.setup).ok, "forced terminal battle initializes")
	var forced_first: Dictionary = forced.submit_command_draft(); check(forced_first.ok, "forced terminal Liu order submits")
	check(forced.submit_sun_control_choice("no", true).ok, "forced terminal Sun AI choice submits")
	for squadron_id in forced._state.combat_effect_state.squadrons:
		var row: Dictionary = forced._state.combat_effect_state.squadrons[squadron_id]
		if String(row.faction_id) == "liu_bei":
			row.current_composition = []; row.hull_points = 0; row.casualties_total = 999; row.damage_state = "destroyed"; row.capabilities.operational = false
	var forced_receipt: Dictionary = forced.resolve_turn()
	check(forced_receipt.ok and forced_receipt.victory_result.winner_faction_id == "cao_cao" and forced.phase() == "battle_concluded", "terminal outcome concludes on the resolved turn")
	check(not forced.continue_turn().ok, "concluded battle rejects next turn")
