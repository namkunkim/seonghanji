extends SceneTree

## GUI renderer acceptance capture. Run with the non-console Godot executable;
## frames come from the product viewport at 1600×900, not a fixture image.

const OUTPUT_DIR := "res://out/demo-rc-qa01-playable-e2e"

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [ProjectSettings.globalize_path(OUTPUT_DIR), name])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# The button signal is the same product route used by pointer activation.
	# OS-level pointer injection is covered by the separate Windows QA surface.
	main.red_cliff_demo_button.emit_signal("pressed")
	await _capture("01-demo-entry-1600x900.png")
	main.red_cliff_banner_action.emit_signal("pressed")
	await _capture("02-phase-1-contact-1600x900.png")
	main.campaign.step()
	await _capture("03-phase-2-barrage-1600x900.png")
	main.red_cliff_battle_view._map.select_fleet("wei_primary")
	await _capture("03a-selected-fleet-1600x900.png")
	main.red_cliff_battle_view._formation.select(3)
	main.red_cliff_battle_view._formation.item_selected.emit(3)
	main.red_cliff_battle_view._toggle_comparison()
	await _capture("03b-formation-comparison-1600x900.png")
	main.red_cliff_battle_view._toggle_comparison()
	main.red_cliff_battle_view._toggle_history()
	await _capture("03c-battle-history-1600x900.png")
	main.red_cliff_battle_view._toggle_history()
	var id := Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID
	for _turn in 4:
		if main.campaign.active_battles[0].status != ActiveBattle.STATUS_ACTIVE:
			break
		main.campaign.issue_red_cliff_player_command(id, "advance_phase")
		main.campaign.step()
		if main.campaign.active_battles[0].combat_phase == 4:
			await _capture("04-phase-4-assault-1600x900.png")
	await _capture("05-resolution-1600x900.png")
	main._close_red_cliff_battle_entry_shell()
	await _capture("06-return-home-1600x900.png")
	main.free()
	quit()

func _init() -> void:
	call_deferred("_run")
