extends SceneTree

## DEMO-RC-QA-01 — product entry through the current turn-battle ceiling.
##
## Canonical demo path only: 적벽 button → G2-01 Liu Bei preparation → G4-01
## turn battle. The superseded Sun-Quan-selectable SCN-03 briefing/manifest/
## long-range-voyage path is out of scope and is never driven here. This test
## uses only real Button.pressed signals and the public Main/view state that
## those signals expose; it never writes turn, phase, winner, damage, or
## resource state directly.
##
## Winner/damage/casualties resolution now lands through DEMO-RC-G8-00~03: the
## per-turn receipt still carries no top-level "winner"/"damage"/"casualties"
## keys (that remains a real invariant — the computed result lives under
## victory_result), and turn 20 now concludes the battle via the turn-limit
## cost-ratio comparison instead of dead-ending pending. Extend this test's
## final assertions to cover the full result screen once G8-04 ships.

const Harness := preload("res://tests/harness.gd")
const OUTPUT_DIR := "res://out/demo-rc-qa01-e2e"

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	call_deferred("_run")


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	var image := root.get_texture().get_image()
	_ok(image != null and image.get_size() == Vector2i(1600, 900), "%s 1600x900 capture available" % label)
	if image != null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		_ok(image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(label + ".png"))) == OK,
			"%s capture saved" % label)


func _run() -> void:
	print("DEMO-RC-QA-01 canonical product entry through turn-limit ceiling")
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_ok(main.red_cliff_demo_button != null and not main.red_cliff_demo_button.disabled,
		"적벽 button is visible and enabled")
	main.red_cliff_demo_button.pressed.emit()
	await process_frame

	var prep: Control = main.get("red_cliff_preparation_view")
	_ok(prep != null and prep.visible, "적벽 button opens the G2-01 Liu Bei preparation screen")
	var prep_state: Dictionary = main.get("red_cliff_preparation_state")
	_eq(prep_state.get("player_faction_id"), "liu_bei", "player is Liu Bei, not Sun Quan")
	_ok(bool(prep_state.get("ready", false)), "historical preparation is ready without preceding event choices")
	await _capture("01-preparation")

	var start_button: Button = prep.find_child("StartTurnBattle", true, false)
	_ok(start_button != null and not start_button.disabled, "StartTurnBattle is visible and enabled")
	start_button.pressed.emit()
	await process_frame

	var view: Control = main.get("red_cliff_turn_battle_view")
	_ok(view != null and view.visible and not prep.visible, "battle start opens the G4-01 turn battle view")
	var battle_state: Dictionary = main.get("red_cliff_turn_battle_state")
	_eq(battle_state.get("phase"), "liu_command", "turn 1 opens on Liu command")
	_eq(int(battle_state.get("turn", 0)), 1, "turn counter starts at 1")
	var controller = view.battle_controller()
	var first_log: Dictionary = controller.turn_log()[0]
	_ok(not first_log.get("resolution_receipt", {}).has("winner")
		and not first_log.get("resolution_receipt", {}).has("damage"),
		"battle start invents no winner or damage")
	await _capture("02-turn-battle-start")

	for turn_number in range(1, 21):
		var primary: Button = view.find_child("PrimaryTurnAction", true, false)
		_ok(primary != null and not primary.disabled, "turn %d primary action available" % turn_number)
		primary.pressed.emit()
		await process_frame
		if String(controller.phase()) == "sun_control_prompt":
			if turn_number == 1:
				# Manual-this-turn only opens Sun's command phase; it still needs
				# a primary press to submit Sun's own HOLD order and resolve.
				view.find_child("SunManualThisTurn", true, false).pressed.emit()
				await process_frame
				view.find_child("PrimaryTurnAction", true, false).pressed.emit()
				await process_frame
			else:
				# Saving the AI/dont-ask policy submits Sun's AI order and
				# resolves the turn in the same action; no extra press needed.
				view.find_child("SunAiDontAsk", true, false).pressed.emit()
				await process_frame
		var expected_phase := "battle_concluded" if turn_number == 20 else "victory_check"
		_eq(String(controller.phase()), expected_phase, "turn %d ledger resolves without a fabricated result" % turn_number)
		var receipt: Dictionary = controller.turn_log()[turn_number - 1].resolution_receipt
		_ok(not receipt.has("winner") and not receipt.has("damage") and not receipt.has("casualties"),
			"turn %d resolution invents no winner, damage, or casualties" % turn_number)
		if turn_number < 20:
			view.find_child("PrimaryTurnAction", true, false).pressed.emit()
			await process_frame

	_eq(String(controller.phase()), "battle_concluded", "20 turns reach a determined result via the turn-limit comparison")
	_ok(view.find_child("TurnHeader", true, false).text.contains("20/20"), "turn header shows 20/20")
	_ok(view.find_child("TurnStatus", true, false).text.contains("승패 확정"), "concluded-result copy is visible")
	_ok(view.find_child("PrimaryTurnAction", true, false).disabled, "primary action locks out at the turn limit")
	await _capture("03-turn-limit-reached")

	_ok(main.campaign != null and main.campaign.active_battles.is_empty(),
		"the new turn battle never touches the legacy Campaign.active_battles path")

	var view_id := view.get_instance_id()
	var return_button: Button = view.find_child("ReturnToPreparation", true, false)
	_ok(return_button != null, "ReturnToPreparation is available at the turn limit")
	return_button.pressed.emit()
	await process_frame
	_ok(prep.visible and not view.visible, "return shows preparation without discarding the resolved battle")
	prep.find_child("StartTurnBattle", true, false).pressed.emit()
	await process_frame
	_eq(main.get("red_cliff_turn_battle_view").get_instance_id(), view_id,
		"re-entry after the turn limit reuses the same battle, not a fresh one")

	main.free()
	print("DEMO-RC-QA-01: %d passed / %d failed" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)
