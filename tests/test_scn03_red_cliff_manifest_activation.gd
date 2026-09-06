extends SceneTree

## G-10 slice 4 — Event 07 participant manifest and the Red-Cliffs activation edge.
const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0
var _data: GameData


func _ok(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  ✗ %s" % message)


func _eq(actual, expected, message: String) -> void:
	_ok(actual == expected, "%s  (%s != %s)" % [message, str(actual), str(expected)])


func _init() -> void:
	_data = GameData.load_all()
	print("SCN-03 적벽 participant manifest · activation")
	_test_manifest_requires_event07_and_canonical_fleets()
	_test_pending_waits_then_activates_once()
	_test_pending_cancellation_reasons()
	_test_save_replay_pending_active_and_manifest_tamper()
	_test_generic_battle_remains_immediate()
	print("\n통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _new_campaign(seed: int) -> Campaign:
	var campaign := Campaign.scenario_03(_data, seed)
	campaign.ai_domestic_enabled = false
	return campaign


func _issue_outcome(campaign: Campaign, event_id: String, outcome: Dictionary) -> void:
	_ok(not campaign.issue_scn03_event_outcome(event_id, outcome).is_empty(),
		"%s outcome 명령 발행" % event_id)
	campaign.step()


func _ready_pending(campaign: Campaign) -> void:
	_issue_outcome(campaign, Campaign.SCN03_EVENT03, {"cao_southward_complete": true})
	_issue_outcome(campaign, Campaign.SCN03_EVENT04, {"sun_quan_independent": true})
	_issue_outcome(campaign, Campaign.SCN03_EVENT06, {"liu_bei_hostile_to_cao": true})
	_issue_outcome(campaign, Campaign.SCN03_EVENT07, {
		"sun_liu_military_pact": true, "yangtze_defense_line": true,
	})


func _first_fleet_id(campaign: Campaign, owner: String) -> int:
	for fleet in campaign.fleets:
		if fleet.owner == owner and fleet.is_alive():
			return fleet.id
	return -1


func _manifest(campaign: Campaign) -> Dictionary:
	var cao_id := _first_fleet_id(campaign, Campaign.SCN03_CAO_OWNER)
	var sun_id := _first_fleet_id(campaign, Campaign.SCN03_SUN_OWNER)
	return {
		"cao_ids": [cao_id],
		"sun_ids": [sun_id],
		"roles": {str(cao_id): "attack", str(sun_id): "defense"},
	}


func _issue_manifest_and_arrive(campaign: Campaign, manifest: Dictionary) -> void:
	_ok(not campaign.issue_scn03_red_cliff_manifest(manifest["cao_ids"], manifest["sun_ids"],
		manifest["roles"]).is_empty(), "Event 07 manifest player 명령 발행")
	campaign.step()


func _pending(campaign: Campaign) -> ActiveBattle:
	return campaign.active_battles[0] if campaign.active_battles.size() == 1 else null


func _move_manifest_fleets_to_red_cliff(campaign: Campaign, manifest: Dictionary) -> void:
	for entry in [[Campaign.SCN03_CAO_OWNER, manifest["cao_ids"][0]],
			[Campaign.SCN03_SUN_OWNER, manifest["sun_ids"][0]]]:
		campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
			"faction": String(entry[0]), "fleet": int(entry[1]), "region": "RGN-04",
		}, 0, "player")
	for _tick in 800:
		if _pending(campaign) != null and _pending(campaign).status == ActiveBattle.STATUS_ACTIVE:
			return
		campaign.step()


func _test_manifest_requires_event07_and_canonical_fleets() -> void:
	print("1. Event 07 prerequisite · manifest validation")
	var before := _new_campaign(20841)
	var early := _manifest(before)
	_ok(before.issue_scn03_red_cliff_manifest(early["cao_ids"], early["sun_ids"], early["roles"]).is_empty(),
		"Event 07 성공 전 manifest 거부")
	_ready_pending(before)
	var manifest := _manifest(before)
	_ok(before.issue_scn03_red_cliff_manifest([manifest["cao_ids"][0]], [manifest["cao_ids"][0]],
		manifest["roles"]).is_empty(), "중복 fleet ID 거부")
	_ok(before.issue_scn03_red_cliff_manifest([999999], manifest["sun_ids"], {
		"999999": "attack", str(manifest["sun_ids"][0]): "defense",
	}).is_empty(), "존재하지 않는 canonical fleet ID는 reducer에서 거부")
	_issue_manifest_and_arrive(before, manifest)
	_eq(before.scn03_red_cliff_manifest["liu_contingent_id"], Campaign.SCN03_LIU_CONTINGENT_ID,
		"유비는 scenario-only contingent ID")
	_eq(_pending(before).status, ActiveBattle.STATUS_PENDING, "미집결은 pending")


func _test_pending_waits_then_activates_once() -> void:
	print("2. incomplete arrivals → one frozen active battle")
	var campaign := _new_campaign(20842)
	_ready_pending(campaign)
	var manifest := _manifest(campaign)
	_issue_manifest_and_arrive(campaign, manifest)
	var battle := _pending(campaign)
	_eq(battle.status, ActiveBattle.STATUS_PENDING, "manifest만으로 active 아님")
	# One required fleet has arrived, but the other has not: still pending.
	campaign._fleet_by_id(int(manifest["cao_ids"][0])).at_system = ActiveBattle.RED_CLIFF_SYSTEM_ID
	campaign.step()
	_eq(battle.status, ActiveBattle.STATUS_PENDING, "불완전 집결은 pending 유지")
	campaign._fleet_by_id(int(manifest["sun_ids"][0])).at_system = ActiveBattle.RED_CLIFF_SYSTEM_ID
	campaign.step()
	_eq(battle.status, ActiveBattle.STATUS_ACTIVE, "필수 실제 함대 전부 도달하면 active")
	_eq(battle.attacker_faction_id, "cao_side", "조조측은 고정 공격 side")
	_eq(battle.defender_faction_id, "sun_liu_side", "손유측은 고정 방어 side")
	_eq(battle.attacker_fleet_ids, [str(manifest["cao_ids"][0])], "공격 참가자 동결")
	_eq(battle.defender_fleet_ids, [str(manifest["sun_ids"][0])], "방어 참가자 동결")
	_eq(battle.participant_roles, manifest["roles"], "역할 동결")
	_eq(battle.campaign_stage, 7, "active의 전역 7단계")
	_eq(battle.combat_phase, 1, "phase는 active에서만 초기화")
	_ok(battle.entry_available, "active에서만 전투 진입 허용")
	var started := battle.started_tick
	campaign.step()
	_eq(battle.started_tick, started, "active 전이는 한 번만")
	battle.activate_red_cliff(["changed"], ["changed"], {"changed": "changed"},
		"changed", started + 1)
	_eq(battle.started_tick, started, "직접 중복 activation도 동결 상태를 덮어쓰지 않음")
	_eq(battle.attacker_fleet_ids, [str(manifest["cao_ids"][0])], "직접 중복도 참가자 불변")


func _test_pending_cancellation_reasons() -> void:
	print("3. pending cancellation reasons never substitute")
	var campaign := _new_campaign(20843)
	_ready_pending(campaign)
	var manifest := _manifest(campaign)
	_issue_manifest_and_arrive(campaign, manifest)
	campaign._fleet_by_id(int(manifest["cao_ids"][0])).ships = 0
	campaign.step()
	var battle := _pending(campaign)
	_eq(battle.status, ActiveBattle.STATUS_CANCELLED, "필수 함대 상실은 pending 취소")
	_eq(battle.cancellation_reason, "required_fleet_destroyed", "취소 사유 고정")
	_ok(not battle.entry_available, "취소 전투 진입 금지")
	var invalid := _new_campaign(208431)
	_ready_pending(invalid)
	var invalid_manifest := _manifest(invalid)
	_issue_manifest_and_arrive(invalid, invalid_manifest)
	invalid._fleet_by_id(int(invalid_manifest["cao_ids"][0])).owner = Campaign.SCN03_SUN_OWNER
	invalid.step()
	_eq(_pending(invalid).cancellation_reason, "manifest_invalid", "소속 변경은 manifest 무효 취소")
	var withdrawn := _new_campaign(208432)
	_ready_pending(withdrawn)
	var withdrawn_manifest := _manifest(withdrawn)
	_issue_manifest_and_arrive(withdrawn, withdrawn_manifest)
	var withdrawing_fleet := withdrawn._fleet_by_id(int(withdrawn_manifest["cao_ids"][0]))
	withdrawing_fleet.at_system = ActiveBattle.RED_CLIFF_SYSTEM_ID
	withdrawing_fleet.target_region = "RGN-01"
	withdrawing_fleet.arrival_tick = withdrawn.world.clock.tick + 2
	withdrawn.step()
	_eq(_pending(withdrawn).cancellation_reason, "required_fleet_withdrawn", "구지 출항은 명시 철수 취소")
	var ending := _new_campaign(208433)
	_ready_pending(ending)
	var ending_manifest := _manifest(ending)
	_issue_manifest_and_arrive(ending, ending_manifest)
	ending.run_to_end(ending.world.clock.tick)
	_eq(_pending(ending).cancellation_reason, "scenario_ended", "시나리오 종료는 pending 취소")


func _test_save_replay_pending_active_and_manifest_tamper() -> void:
	print("4. pending/active save replay · manifest tamper")
	var pending_source := _new_campaign(20844)
	_ready_pending(pending_source)
	var manifest := _manifest(pending_source)
	_issue_manifest_and_arrive(pending_source, manifest)
	var pending_save := pending_source.to_save_dict()
	var pending_restored := Campaign.from_save_result(pending_save, _data)
	_eq(pending_restored["status"], Save.STATUS_OK, "pending manifest save replay")
	_eq(pending_restored["actual_digest"], pending_source.digest(), "pending replay digest")
	var tampered: Dictionary = pending_save.duplicate(true)
	tampered["world"]["commands"][4]["payload"]["fleet_roles"][str(manifest["cao_ids"][0])] = "changed"
	_eq(Campaign.from_save_result(tampered, _data)["status"], Save.STATUS_VERIFICATION_FAILED,
		"유효 schema manifest 변조는 digest 검출")
	var active_source := _new_campaign(20845)
	_ready_pending(active_source)
	var active_manifest := _manifest(active_source)
	_issue_manifest_and_arrive(active_source, active_manifest)
	_move_manifest_fleets_to_red_cliff(active_source, active_manifest)
	_eq(_pending(active_source).status, ActiveBattle.STATUS_ACTIVE, "명령 이동으로 active 도달")
	var active_restored := Campaign.from_save_result(active_source.to_save_dict(), _data)
	_eq(active_restored["status"], Save.STATUS_OK, "active save replay")
	_eq(active_restored["actual_digest"], active_source.digest(), "active replay digest")


func _test_generic_battle_remains_immediate() -> void:
	print("5. unlisted generic battle remains immediate")
	var campaign := _new_campaign(20846)
	var region_id := ""
	for rid in _data.region_ids:
		if String(campaign.world.region_states[rid].owner) == Campaign.SCN03_SUN_OWNER:
			region_id = rid
			break
	var attacker := Fleet.new()
	attacker.id = 99801
	attacker.owner = Campaign.SCN03_CAO_OWNER
	attacker.at_system = _data.system_of(region_id)
	attacker.ships = Battle.FLEET_SHIPS
	campaign.fleets.append(attacker)
	var before := campaign.battles
	campaign._resolve_battle(attacker, region_id)
	_eq(campaign.battles, before + 1, "unlisted battle uses existing immediate resolver")
	_eq(campaign.active_battles.size(), 0, "generic battle creates no active Red-Cliffs record")
