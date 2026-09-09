extends SceneTree

## Contract test: receipts stay empty on rejection for old callers, while
## red_cliff_command_state exposes stable reason codes and canonical evidence.
const Harness := preload("res://tests/harness.gd")
var data: GameData
var failures := 0

func _ok(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("  x %s" % label)

func _init() -> void:
	data = GameData.load_all()
	var campaign := _active_campaign()
	var battle: ActiveBattle = campaign.active_battles[0]
	print("Red-Cliffs command feedback and decision evidence")
	# Phase 1 is the automatic contact window, so an advance is structurally refused.
	_ok(campaign.issue_red_cliff_player_command(battle.battle_id, "advance_phase").is_empty(), "phase 1 receipt remains empty")
	_ok(campaign.red_cliff_command_state(battle.battle_id, "advance_phase")["requested_command"]["reason_code"] == "phase_not_ready", "sequence reason exposed")
	campaign.step()
	var hold := campaign.issue_red_cliff_player_command(battle.battle_id, "hold_formation")
	_ok(bool(hold.get("accepted", false)) and hold.get("reason_code", "") == "queued", "success has structured receipt")
	campaign.step()
	_ok(campaign.issue_red_cliff_player_command(battle.battle_id, "hold_formation").is_empty(), "duplicate receipt remains empty")
	_ok(campaign.red_cliff_command_state(battle.battle_id, "hold_formation")["requested_command"]["reason_code"] == "duplicate_command", "duplicate reason exposed")
	var attacker := campaign._fleet_by_id(int(battle.attacker_fleet_ids[0]))
	var saved_command := attacker.command
	attacker.command = -1
	var target := ""
	for row in Formations.rows():
		if String(row["id"]) != battle.attacker_formation_id:
			target = String(row["id"])
			break
	_ok(campaign.issue_red_cliff_player_command(battle.battle_id, "change_formation", {"target_formation_id": target}).is_empty(), "insufficient command receipt remains empty")
	_ok(campaign.red_cliff_command_state(battle.battle_id, "change_formation", {"target_formation_id": target})["requested_command"]["reason_code"] == "insufficient_command", "command reason exposed")
	attacker.command = saved_command
	_ok(not campaign.issue_red_cliff_player_command(battle.battle_id, "delegate_ai").is_empty(), "delegate receipt accepted")
	campaign.step()
	_ok(campaign.red_cliff_command_state(battle.battle_id, "advance_phase")["requested_command"]["reason_code"] == "ai_delegated", "AI delegation reason exposed")
	for _tick in 8:
		if battle.status == ActiveBattle.STATUS_RESOLVED: break
		campaign.step()
	_ok(battle.status == ActiveBattle.STATUS_RESOLVED, "AI resolves fixed five-phase battle")
	_ok(campaign.issue_red_cliff_player_command(battle.battle_id, "advance_phase").is_empty(), "resolved receipt remains empty")
	_ok(campaign.red_cliff_command_state(battle.battle_id, "advance_phase")["requested_command"]["reason_code"] == "resolved", "resolved reason exposed")
	var decision: Dictionary = battle.result.get("decision", {})
	_ok(decision.get("reason_code", "") == "phase_five_score" and decision.has("attacker") and decision.has("defender"), "canonical decision evidence exists")
	_ok(decision["attacker"].has("ships_remaining") and decision["defender"].has("collapsed"), "evidence has UI-ready totals and collapse")
	print("Red-Cliffs command feedback: %d failures" % failures)
	quit(Harness.EXIT_FAIL if failures > 0 else Harness.EXIT_PASS)

func _active_campaign() -> Campaign:
	var campaign := Campaign.scenario_03(data, 77031)
	campaign.ai_domestic_enabled = false
	for event in [[Campaign.SCN03_EVENT03,{"cao_southward_complete":true}], [Campaign.SCN03_EVENT04,{"sun_quan_independent":true}], [Campaign.SCN03_EVENT06,{"liu_bei_hostile_to_cao":true}], [Campaign.SCN03_EVENT07,{"sun_liu_military_pact":true,"yangtze_defense_line":true}]]:
		campaign.issue_scn03_event_outcome(String(event[0]), event[1])
		campaign.step()
	var cao := -1; var sun := -1
	for fleet in campaign.fleets:
		if fleet.owner == Campaign.SCN03_CAO_OWNER and cao < 0: cao = fleet.id
		if fleet.owner == Campaign.SCN03_SUN_OWNER and sun < 0: sun = fleet.id
	campaign.issue_scn03_red_cliff_manifest([cao],[sun],{str(cao):"attack",str(sun):"defense"})
	campaign.step()
	for entry in [[Campaign.SCN03_CAO_OWNER,cao],[Campaign.SCN03_SUN_OWNER,sun]]:
		campaign.world.issue(Domestic.CMD_FLEET_MOVE,{"faction":String(entry[0]),"fleet":int(entry[1]),"region":"RGN-04"},0,"player")
	for _tick in 800:
		if campaign.active_battles.size() == 1 and campaign.active_battles[0].status == ActiveBattle.STATUS_ACTIVE: return campaign
		campaign.step()
	return campaign
