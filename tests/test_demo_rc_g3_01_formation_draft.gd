extends SceneTree

## Task ID: DEMO-RC-G3-01
## 공식 작업 제목: 비용 기반 전대·함대 편성 편집기
## 새 작업 제목: DEMO-RC-G3-01 — 비용 기반 전대·함대 편성 편집기

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")

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


func _run() -> void:
	print("DEMO-RC-G3-01 formation draft core")
	_test_setup_data_and_boundaries()
	_test_snapshots_and_mutations()
	_test_separate_historical_and_applied_lifetime()
	_test_inventory_summary()
	_test_permissions_and_atomic_apply()
	_test_fleet_operations_and_flagship_order()
	_test_overcap_curve()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _valid_setup() -> Dictionary:
	var result := Setup.load_default()
	_ok(bool(result.get("ok", false)), "default G3 setup validates")
	return result.get("setup", {})


func _new_draft(setup: Dictionary = {}) -> RefCounted:
	if setup.is_empty():
		setup = _valid_setup()
	return Draft.new(setup)


func _test_setup_data_and_boundaries() -> void:
	var setup := _valid_setup()
	if setup.is_empty(): return
	_ok(setup.get("command_limit_rules") is Dictionary, "command-limit rules are explicit data")
	_ok(setup.get("fleet_groups") is Array, "fleet groups are explicit data")
	var rules: Dictionary = setup.command_limit_rules
	_eq(rules.recommended_base_cost, 40, "recommended base cost")
	_eq(rules.recommended_cost_per_command, 2, "recommended command multiplier")
	_eq(rules.over_tier_ratio, 0.25, "over-cap tier ratio")
	_eq(rules.max_penalty_tier, 4, "over-cap max tier")
	_eq(int(rules.penalty_per_tier.mobility_percent), 5, "official mobility penalty")
	_eq(int(rules.penalty_per_tier.accuracy_percent), 4, "official accuracy penalty")
	_eq(int(rules.penalty_per_tier.formation_change_percent), 8, "official formation-change penalty")
	var liu_count := 0
	for squad in setup.squadrons:
		if String(squad.faction_id) == "liu_bei": liu_count += 1
	_eq(liu_count, 2, "Liu Bei has at least two editable squadrons")
	for faction in setup.factions:
		_eq(faction.inventory.size(), setup.ship_types.size(), "inventory covers every ship type: %s" % faction.id)
		for commander in faction.demo_roster:
			_ok(commander.has("command") and commander.has("level"), "roster command and level: %s" % commander.id)

	var bad := setup.duplicate(true)
	bad.command_limit_rules.recommended_base_cost = 41
	_ok(not Setup.validate_document(bad).ok, "non-official command rule rejected")
	bad = setup.duplicate(true)
	bad.factions[0].inventory.erase("SHP-01")
	_ok(not Setup.validate_document(bad).ok, "missing inventory ship rejected")
	bad = setup.duplicate(true)
	bad.factions[0].inventory["SHP-01"] = -1
	_ok(not Setup.validate_document(bad).ok, "negative inventory rejected")
	bad = setup.duplicate(true)
	bad.squadrons.remove_at(1)
	bad.fleet_groups[0].squadron_ids = ["RC-LIU-SQ-01"]
	bad.fleet_groups[0].flagship_squadron_id = "RC-LIU-SQ-01"
	bad.squadrons[0].flagship = true
	_ok(not Setup.validate_document(bad).ok, "Liu minimum two squadrons enforced")
	bad = setup.duplicate(true)
	bad.squadrons[0].commander = bad.squadrons[1].commander.duplicate(true)
	_ok(not Setup.validate_document(bad).ok, "same-faction commander duplication rejected")
	bad = setup.duplicate(true)
	for component in bad.squadrons[0].composition: component.count = 0
	bad.squadrons[0].declared_total_cost = 0
	_ok(not Setup.validate_document(bad).ok, "zero-ship squadron rejected")
	bad = setup.duplicate(true)
	bad.fleet_groups[0].squadron_ids.append("RC-LIU-SQ-01")
	_ok(not Setup.validate_document(bad).ok, "duplicate fleet membership rejected")
	bad = setup.duplicate(true)
	bad.squadrons[0].deployment = {"kind": "independent"}
	_ok(not Setup.validate_document(bad).ok, "independent squadron cannot remain in a fleet")


func _test_snapshots_and_mutations() -> void:
	var editor = _new_draft()
	var historical: Dictionary = editor.historical_snapshot()
	var historical_digest: String = JSON.stringify(historical)
	var leaked: Dictionary = editor.draft_snapshot()
	leaked.squadrons[0].name = "외부 변조"
	_eq(JSON.stringify(editor.historical_snapshot()), historical_digest, "historical snapshot is a deep copy")
	_ok(String(editor.draft_snapshot().squadrons[0].name) != "외부 변조", "draft snapshot is a deep copy")

	_ok(editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", 5).ok, "Liu composition count mutates")
	_ok(editor.set_fast_equipment("RC-LIU-SQ-01", "FAST-EQ-TORPEDO").ok, "fast-craft equipment mutates")
	_ok(editor.set_commander("RC-LIU-SQ-01", "CHR-0136").ok, "same-faction unused commander mutates")
	_ok(editor.set_formation("RC-LIU-SQ-01", "FRM-07").ok, "formation mutates")
	_ok(editor.set_position("RC-LIU-SQ-01", Vector2(0, 900)).ok, "inclusive battlefield edge accepted")
	var squad := _find_squad(editor.draft_snapshot(), "RC-LIU-SQ-01")
	_eq(squad.formation_id, "FRM-07", "formation persisted in draft")
	_eq(squad.commander.id, "CHR-0136", "commander persisted in draft")
	_eq(squad.initial_position, [0.0, 900.0], "position persisted in draft")
	_eq(squad.declared_total_cost, 95, "composition and exact equipment cost recalculated")
	_ok(editor.validate_draft().ok, "valid mutations produce a valid draft")

	_ok(not editor.set_ship_count("RC-LIU-SQ-01", "SHP-UNKNOWN", 1).ok, "unknown ship rejected")
	_ok(not editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", -1).ok, "negative count rejected")
	_ok(not editor.set_fast_equipment("RC-LIU-SQ-01", "FAST-EQ-UNKNOWN").ok, "unknown fast equipment rejected")
	_ok(not editor.set_commander("RC-LIU-SQ-01", "CHR-0211").ok, "other-faction commander rejected")
	_ok(not editor.set_commander("RC-LIU-SQ-01", "CHR-0134").ok, "same-faction duplicate commander rejected")
	_ok(not editor.set_formation("RC-LIU-SQ-01", "FRM-08").ok, "unknown formation rejected")
	_ok(not editor.set_position("RC-LIU-SQ-01", Vector2(1601, 450)).ok, "out-of-bounds position rejected")

	_ok(editor.cancel().ok, "cancel succeeds")
	_eq(editor.draft_digest(), editor.applied_digest(), "cancel restores applied snapshot")
	_ok(editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", 5).ok, "mutation before historical restore")
	_ok(editor.restore_historical().ok, "historical restore succeeds")
	_eq(editor.draft_digest(), historical_digest, "historical restore is exact")


func _test_separate_historical_and_applied_lifetime() -> void:
	var historical := _valid_setup()
	var first = _new_draft(historical)
	_ok(first.set_formation("RC-LIU-SQ-01", "FRM-07").ok, "lifetime custom formation staged")
	_ok(first.apply().ok, "lifetime custom formation applied")
	var current: Dictionary = first.applied_snapshot()
	var reopened = Draft.new()
	_ok(reopened.configure(historical, current).ok, "reopen accepts separate historical and applied inputs")
	_eq(reopened.applied_digest(), JSON.stringify(current), "reopen starts from current applied setup")
	_ok(reopened.restore_historical().ok, "reopen restores original historical baseline to draft")
	_eq(reopened.draft_digest(), JSON.stringify(historical), "restored draft is original G2 baseline")
	_eq(reopened.applied_digest(), JSON.stringify(current), "historical restore leaves custom applied setup unchanged")
	_ok(reopened.cancel().ok, "cancel after restore succeeds")
	_eq(reopened.draft_digest(), JSON.stringify(current), "cancel returns to current applied setup")


func _test_inventory_summary() -> void:
	var editor = _new_draft()
	var liu: Dictionary = editor.faction_inventory_summary("liu_bei")
	_ok(liu.ok, "known faction inventory summary succeeds")
	_eq(liu.inventory.size(), 8, "inventory summary covers every ship type")
	_eq(liu.inventory["SHP-04"], {"total": 10, "used": 7, "available": 3},
		"historical Liu line-ship inventory is calculated")
	_eq(liu.inventory["SHP-08"], {"total": 16, "used": 6, "available": 10},
		"historical Liu fast-craft inventory is calculated")
	_ok(editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", 5).ok, "inventory test stages count change")
	var changed: Dictionary = editor.faction_inventory_summary("liu_bei")
	_eq(changed.inventory["SHP-04"], {"total": 10, "used": 8, "available": 2},
		"inventory summary reflects draft count immediately")
	var sun_before: Dictionary = editor.faction_inventory_summary("sun_quan")
	editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", 6)
	var sun_after: Dictionary = editor.faction_inventory_summary("sun_quan")
	_eq(sun_after.inventory, sun_before.inventory, "Liu mutation does not leak into Sun inventory")
	_eq(sun_after.inventory["SHP-04"], {"total": 14, "used": 5, "available": 9},
		"Sun summary counts only Sun squadrons")
	var invalid: Dictionary = editor.faction_inventory_summary("unknown_faction")
	_ok(not invalid.ok and not invalid.errors.is_empty(), "unknown faction inventory returns explicit error")
	_eq(invalid.inventory, {}, "unknown faction inventory result is empty")


func _test_permissions_and_atomic_apply() -> void:
	var editor = _new_draft()
	_ok(editor.can_edit_faction("liu_bei"), "Liu is editable")
	_ok(not editor.set_formation("RC-SUN-SQ-01", "FRM-01").ok, "Sun is opt-in read-only")
	_ok(editor.set_sun_manual(true).ok, "Sun manual opt-in enabled")
	_ok(editor.set_formation("RC-SUN-SQ-01", "FRM-01").ok, "Sun edits after opt-in")
	_ok(not editor.set_formation("RC-CAO-SQ-01", "FRM-01").ok, "Cao is always read-only")
	_ok(editor.set_sun_manual(false).ok, "Sun manual opt-in disabled")
	_eq(_find_squad(editor.draft_snapshot(), "RC-SUN-SQ-01").formation_id, "FRM-02",
		"disabling Sun manual restores applied Sun state")

	var before: String = editor.applied_digest()
	_ok(editor.set_ship_count("RC-LIU-SQ-01", "SHP-01", 2).ok, "inventory-exceeding draft mutation is staged")
	var invalid: Dictionary = editor.apply()
	_ok(not invalid.ok, "inventory-exceeding apply rejected")
	_eq(editor.applied_digest(), before, "invalid apply leaves applied digest unchanged")
	_eq(invalid.digest, before, "invalid result reports unchanged digest")
	_ok(editor.cancel().ok, "cancel after invalid apply")
	_ok(editor.set_formation("RC-LIU-SQ-01", "FRM-07").ok, "valid atomic mutation staged")
	var valid: Dictionary = editor.apply()
	_ok(valid.ok, "valid apply succeeds")
	_eq(valid.setup.formation_revision, 1, "apply increments revision once")
	_eq(editor.draft_digest(), editor.applied_digest(), "successful apply atomically aligns snapshots")
	_ok(editor.set_formation("RC-LIU-SQ-01", "FRM-06").ok, "second mutation staged")
	_ok(editor.apply().ok, "second apply succeeds")
	_eq(editor.applied_snapshot().formation_revision, 2, "revision increments from applied state")


func _test_fleet_operations_and_flagship_order() -> void:
	var editor = _new_draft()
	_eq(_find_fleet(editor.draft_snapshot(), "RC-LIU-FLT-01").flagship_squadron_id, "RC-LIU-SQ-02",
		"higher command automatically selects flagship")
	_ok(editor.unassign_to_independent("RC-LIU-SQ-02").ok, "squadron can become independent")
	var independent := _find_squad(editor.draft_snapshot(), "RC-LIU-SQ-02")
	_eq(independent.deployment.kind, "independent", "independent deployment stored")
	_ok(not independent.flagship, "independent squadron is not fleet flagship")
	var created: Dictionary = editor.create_fleet("liu_bei", "  신설 별동함대  ", ["RC-LIU-SQ-02"])
	_ok(created.ok, "fleet create succeeds")
	var fleet_id := String(created.get("fleet_id", ""))
	_ok(fleet_id.begins_with("RC-USER-LIU_BEI-FLT-"), "created fleet receives stable generated ID")
	_ok(editor.rename_fleet(fleet_id, "별동함대").ok, "fleet rename succeeds")
	_ok(editor.assign_to_fleet("RC-LIU-SQ-01", fleet_id).ok, "same-faction fleet assignment succeeds")
	var fleet := _find_fleet(editor.draft_snapshot(), fleet_id)
	_eq(fleet.squadron_ids.size(), 2, "fleet has unique two-squadron membership")
	_eq(fleet.flagship_squadron_id, "RC-LIU-SQ-02", "higher command wins after assignment")
	_ok(not editor.assign_to_fleet("RC-SUN-SQ-01", fleet_id).ok, "cross-faction assignment rejected")
	_ok(not editor.create_fleet("cao_cao", "금지", ["RC-CAO-SQ-01"]).ok, "Cao fleet create rejected")
	_ok(editor.apply().ok, "fleet edit applies")

	var level_setup := _valid_setup()
	_set_roster_stat(level_setup, "liu_bei", "CHR-0128", 90, 8)
	_set_roster_stat(level_setup, "liu_bei", "CHR-0134", 90, 9)
	var level_editor = _new_draft(level_setup)
	level_editor.set_formation("RC-LIU-SQ-01", "FRM-02")
	_eq(_find_fleet(level_editor.draft_snapshot(), "RC-LIU-FLT-01").flagship_squadron_id, "RC-LIU-SQ-02",
		"level breaks equal-command flagship tie")

	var id_setup := _valid_setup()
	_set_roster_stat(id_setup, "liu_bei", "CHR-0128", 90, 8)
	_set_roster_stat(id_setup, "liu_bei", "CHR-0134", 90, 8)
	var id_editor = _new_draft(id_setup)
	id_editor.set_formation("RC-LIU-SQ-01", "FRM-02")
	_eq(_find_fleet(id_editor.draft_snapshot(), "RC-LIU-FLT-01").flagship_squadron_id, "RC-LIU-SQ-01",
		"stable squadron ID breaks equal command and level tie")


func _test_overcap_curve() -> void:
	var editor = _new_draft()
	var base: Dictionary = editor.squadron_metrics("RC-LIU-SQ-01")
	_eq(base.recommended_cost, 204, "recommended cost is 40 + command x 2")
	_eq(base.penalty_tier, 0, "historical Liu squadron is not over cap")
	# SHP-04 cost 10. 21 ships cost 210: 6/204 over, ceil(0.0294/0.25) = tier 1.
	editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", 21)
	var tier1: Dictionary = editor.squadron_metrics("RC-LIU-SQ-01")
	_eq(tier1.penalty_tier, 1, "over ratio rounds upward to tier one")
	_eq([tier1.mobility_percent, tier1.accuracy_percent, tier1.formation_change_percent], [-5, -4, -8],
		"tier one penalties")
	# Inventory validation is independent; metrics still cap extreme previews at tier 4.
	editor.set_ship_count("RC-LIU-SQ-01", "SHP-04", 100)
	var tier4: Dictionary = editor.squadron_metrics("RC-LIU-SQ-01")
	_eq(tier4.penalty_tier, 4, "extreme over cap is clamped to tier four")
	_eq([tier4.mobility_percent, tier4.accuracy_percent, tier4.formation_change_percent], [-20, -16, -32],
		"tier four penalties")
	_ok(tier4.warning, "over cap emits warning but mutation remains staged")

	var legal = _new_draft()
	# Leave the second Liu squadron's stock in place and concentrate the remaining stock.
	for change in [["SHP-01", 1], ["SHP-02", 2], ["SHP-03", 3], ["SHP-04", 7],
			["SHP-05", 2], ["SHP-06", 3], ["SHP-07", 6], ["SHP-08", 10]]:
		_ok(legal.set_ship_count("RC-LIU-SQ-01", String(change[0]), int(change[1])).ok,
			"legal over-cap composition stage: %s" % change[0])
	var legal_metrics: Dictionary = legal.squadron_metrics("RC-LIU-SQ-01")
	_ok(legal_metrics.warning and legal_metrics.penalty_tier > 0, "inventory-valid over cap warns")
	_ok(legal.apply().ok, "over cap is allowed when every hard invariant is valid")


func _find_squad(setup: Dictionary, squadron_id: String) -> Dictionary:
	for squad in setup.get("squadrons", []):
		if String(squad.get("id", "")) == squadron_id: return squad
	return {}


func _find_fleet(setup: Dictionary, fleet_id: String) -> Dictionary:
	for fleet in setup.get("fleet_groups", []):
		if String(fleet.get("id", "")) == fleet_id: return fleet
	return {}


func _set_roster_stat(setup: Dictionary, faction_id: String, commander_id: String, command: int, level: int) -> void:
	for faction in setup.factions:
		if String(faction.id) != faction_id: continue
		for commander in faction.demo_roster:
			if String(commander.id) == commander_id:
				commander.command = command
				commander.level = level
				return
