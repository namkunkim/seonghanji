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
	_test_combined_alliance_threshold(resolver)
	_test_sun_solo_defeat_never_alone_ends_alliance(resolver)
	_test_reason_code_priority(resolver)
	_test_simultaneous_with_combined_alliance_defeat(resolver)
	_test_turn_boundary_alliance_evidence()
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed else Harness.EXIT_PASS)


func _row(original: int, remaining: int, squadron_count := 1, surrendered := 0) -> Dictionary:
	return {"original_cost": original, "remaining_cost": remaining, "squadron_count": squadron_count, "surrendered_squadron_count": surrendered}


func _inputs(liu: Dictionary, sun: Dictionary, cao: Dictionary) -> Dictionary:
	return {"turn": 4, "factions": {"liu_bei": liu, "sun_quan": sun, "cao_cao": cao}}


func _test_combined_alliance_threshold(resolver) -> void:
	# Liu alone loses only 40% (100->60, below 7000bp) and Sun Quan is wiped
	# out (100->0), but the *combined* alliance cost lands exactly on the
	# 7000bp threshold: (200-60)/200 = 7000bp.
	var at_threshold: Dictionary = resolver.evaluate(_inputs(_row(100, 60), _row(100, 0), _row(100, 100)))
	check(at_threshold.ok and at_threshold.winner_faction_id == "cao_cao" and at_threshold.reason_codes == ["alliance_combined_loss_threshold"],
		"combined alliance loss at exactly 7000bp defeats the alliance even though Liu alone is under threshold")
	check(at_threshold.alliance_evidence.original_cost == 200 and at_threshold.alliance_evidence.remaining_cost == 60 \
		and at_threshold.alliance_evidence.loss_basis_points == 7000 and at_threshold.alliance_evidence.loss_threshold_reached, "alliance_evidence reports the combined totals")
	check(at_threshold.alliance_evidence.member_faction_ids == ["liu_bei", "sun_quan"], "alliance_evidence names the alliance members")
	# One basis point under the threshold must not end the battle.
	var below_threshold: Dictionary = resolver.evaluate(_inputs(_row(100, 61), _row(100, 0), _row(100, 100)))
	check(below_threshold.ok and not below_threshold.winner_present and not below_threshold.alliance_evidence.loss_threshold_reached,
		"combined alliance loss one basis point under threshold does not end the battle")
	# Asymmetric partial losses on both members that never combine past 70%.
	var partial: Dictionary = resolver.evaluate(_inputs(_row(100, 80), _row(100, 50), _row(100, 100)))
	check(partial.ok and not partial.winner_present, "asymmetric partial losses under combined 70 percent do not end the battle")


func _test_sun_solo_defeat_never_alone_ends_alliance(resolver) -> void:
	# Sun Quan's own 70%bp cost loss does not by itself defeat the alliance
	# when the combined total still stays under threshold (pre-existing
	# G8-01 behavior, re-asserted here against the new combined check).
	var sun_cost_loss: Dictionary = resolver.evaluate(_inputs(_row(100, 100), _row(100, 30), _row(100, 100)))
	check(sun_cost_loss.ok and not sun_cost_loss.winner_present and not sun_cost_loss.alliance_evidence.loss_threshold_reached,
		"Sun Quan's own 70 percent cost loss alone does not end the alliance")
	# Sun Quan's full morale collapse (all squadrons surrendered) does not
	# reduce cost, so it must not contribute to the combined loss check.
	var sun_morale_collapse: Dictionary = resolver.evaluate(_inputs(_row(100, 100), _row(100, 100, 1, 1), _row(100, 100)))
	check(sun_morale_collapse.ok and not sun_morale_collapse.winner_present and sun_morale_collapse.alliance_evidence.loss_basis_points == 0,
		"Sun Quan's own morale collapse does not affect the combined-cost alliance check")


func _test_reason_code_priority(resolver) -> void:
	# When Liu Bei's own terminal condition is already met, the reason code
	# names that condition even though the combined check would also fire.
	var liu_own: Dictionary = resolver.evaluate(_inputs(_row(100, 20), _row(100, 100), _row(100, 100)))
	check(liu_own.ok and liu_own.winner_faction_id == "cao_cao" and liu_own.reason_codes == ["liu_bei_terminal_condition"],
		"Liu Bei's own terminal condition takes reason-code priority over the combined check")


func _test_simultaneous_with_combined_alliance_defeat(resolver) -> void:
	# The alliance falls only via the combined check (Liu alone is under
	# threshold) while Cao Cao also falls in the same resolved turn: Cao
	# priority still applies and the reason code stays the shared one.
	var simultaneous: Dictionary = resolver.evaluate(_inputs(_row(100, 60), _row(100, 0), _row(100, 20)))
	check(simultaneous.ok and simultaneous.winner_faction_id == "cao_cao" and simultaneous.reason_codes == ["simultaneous_terminal_conditions_cao_priority"],
		"combined-only alliance defeat still yields to Cao priority on simultaneous terminal conditions")


func _test_turn_boundary_alliance_evidence() -> void:
	var loaded := Setup.load_default(); check(loaded.ok, "default setup loads")
	var battle := Battle.new(); check(battle.initialize(loaded.setup).ok, "battle initializes victory resolver")
	var first: Dictionary = battle.submit_command_draft(); check(first.ok, "Liu orders submit")
	check(battle.submit_sun_control_choice("no", true).ok, "Sun AI choice submits")
	var receipt: Dictionary = battle.resolve_turn()
	check(receipt.ok and receipt.victory_result.has("alliance_evidence") and not receipt.victory_result.alliance_evidence.loss_threshold_reached,
		"resolved receipt carries alliance_evidence alongside the existing per-faction evidence")
