class_name ActiveBattle
extends RefCounted

## G-10 slice 3 — the smallest replay-derived persistent battle contract.
##
## `SCN-03-E09-RED-CLIFF-01` is canonical: scenario Event 09 + fixed Red-Cliffs
## ordinal 01. It intentionally does not use a UI label, fleet choice, region owner,
## power ratio, diplomacy tier, or object address. This slice creates `pending` only.

const STATUS_PENDING: String = "pending"
const STATUS_ACTIVE: String = "active"
const STATUS_RESOLVED: String = "resolved"
const STATUS_CANCELLED: String = "cancelled"
const RED_CLIFF_REGION_ID: String = "RGN-04"
const RED_CLIFF_SYSTEM_ID: String = "SYS-13"
## Canonical map-body identity for the display anchor named 구지 (Guji).
const RED_CLIFF_ANCHOR_BODY_ID: String = "BODY-RGN-04-01"

var battle_id: String = ""
var cause_event_id: String = ""
var scenario_id: String = "SCN-03"
var status: String = STATUS_PENDING

## Authority location is fixed by the approved scenario contract. Guji is a display
## anchor only; neither field is a region-ownership precondition.
var region_id: String = RED_CLIFF_REGION_ID
var system_id: String = RED_CLIFF_SYSTEM_ID
var anchor_body_id: String = RED_CLIFF_ANCHOR_BODY_ID

var created_tick: int = 0
## Undefined while pending.  The phase engine is intentionally out of this slice;
## activation merely establishes its deterministic first phase.
var started_tick: int = -1
var campaign_stage: int = 0
var combat_phase: int = -1
## The first narrow active slice advances Contact (1) to Barrage (2) on the next
## campaign tick.  A later battle engine owns phases 3–5; it must not rewrite this
## recorded transition.
var phase_advanced_tick: int = -1
var resolved_tick: int = -1
## Result is deliberately a small, canonical player-input fact.  It is not a
## hidden combat calculation or a UI snapshot: the campaign reducer applies it
## once after phase 2 and replay derives the same resolved record from the log.
var result: Dictionary = {}
var result_applied: bool = false
var cancelled_tick: int = -1
var cancellation_reason: String = ""
## Reserved deterministic anchor for a later phase engine. It consumes no Rng stream.
var rng_anchor: String = ""

## DEMO-RC-02 persistent state. It is replay-derived from commands, never a save
## snapshot authority.
var phase_started_tick: int = -1
var phase_ended_ticks: Dictionary = {}
var attacker_ships: int = 0
var defender_ships: int = 0
var attacker_morale: int = 100
var defender_morale: int = 100
var attacker_formation_id: String = ""
var defender_formation_id: String = ""
var applied_schemes: Array[Dictionary] = []
var phase_results: Array[Dictionary] = []
var player_commands: Array[Dictionary] = []
var ai_decisions: Array[Dictionary] = []
var ai_delegated: bool = false
var campaign_result_applied: bool = false

## Pending does not select forces or assign roles. Keep every participant surface
## explicitly empty until activation owns that decision.
var attacker_faction_id: String = ""
var defender_faction_id: String = ""
var attacker_fleet_ids: Array[String] = []
var defender_fleet_ids: Array[String] = []
var participant_roles: Dictionary = {}
## A scenario participant, not a general faction or Fleet.  It never enters fleet
## arrival checks and exists only when the approved Event 07 manifest says so.
var liu_contingent_id: String = ""
var entry_available: bool = false


static func red_cliff_pending(created_at_tick: int, canonical_id: String,
		cause_id: String) -> ActiveBattle:
	var battle := ActiveBattle.new()
	battle.battle_id = canonical_id
	battle.cause_event_id = cause_id
	battle.created_tick = created_at_tick
	battle.rng_anchor = "%d|%s" % [created_at_tick, canonical_id]
	battle._normalize_pending_identity()
	return battle


func _normalize_pending_identity() -> void:
	attacker_fleet_ids.sort()
	defender_fleet_ids.sort()
	# A pending record may not smuggle participant assignments through an arbitrary map.
	participant_roles.clear()
	attacker_faction_id = ""
	defender_faction_id = ""
	entry_available = false
	status = STATUS_PENDING
	started_tick = -1
	campaign_stage = 0
	combat_phase = -1
	phase_advanced_tick = -1
	resolved_tick = -1
	result.clear()
	result_applied = false
	cancelled_tick = -1
	cancellation_reason = ""
	liu_contingent_id = ""
	phase_started_tick = -1
	phase_ended_ticks.clear()
	attacker_ships = 0
	defender_ships = 0
	attacker_morale = 100
	defender_morale = 100
	attacker_formation_id = ""
	defender_formation_id = ""
	applied_schemes.clear()
	phase_results.clear()
	player_commands.clear()
	ai_decisions.clear()
	ai_delegated = false
	campaign_result_applied = false


func activate_red_cliff(attacker_ids: Array[String], defender_ids: Array[String],
		roles: Dictionary, contingent_id: String, at_tick: int) -> void:
	if status != STATUS_PENDING:
		return
	attacker_fleet_ids = attacker_ids.duplicate()
	defender_fleet_ids = defender_ids.duplicate()
	attacker_fleet_ids.sort()
	defender_fleet_ids.sort()
	participant_roles = roles.duplicate(true)
	attacker_faction_id = "cao_side"
	defender_faction_id = "sun_liu_side"
	liu_contingent_id = contingent_id
	started_tick = at_tick
	campaign_stage = 7
	combat_phase = 1
	phase_advanced_tick = -1
	resolved_tick = -1
	result.clear()
	result_applied = false
	cancelled_tick = -1
	cancellation_reason = ""
	entry_available = true
	status = STATUS_ACTIVE
	phase_started_tick = at_tick


func initialize_red_cliff_state(attacker_ship_count: int, defender_ship_count: int,
		attacker_initial_morale: int, defender_initial_morale: int,
		attacker_initial_formation: String, defender_initial_formation: String) -> void:
	if status != STATUS_ACTIVE or combat_phase != 1 or not phase_results.is_empty():
		return
	attacker_ships = maxi(0, attacker_ship_count)
	defender_ships = maxi(0, defender_ship_count)
	attacker_morale = clampi(attacker_initial_morale, 0, Battle.MORALE_MAX)
	defender_morale = clampi(defender_initial_morale, 0, Battle.MORALE_MAX)
	attacker_formation_id = attacker_initial_formation
	defender_formation_id = defender_initial_formation


func cancel_pending(at_tick: int, reason: String) -> void:
	if status != STATUS_PENDING:
		return
	cancelled_tick = at_tick
	cancellation_reason = reason
	entry_available = false
	status = STATUS_CANCELLED


## Contact is visible for the activation tick only.  This is a deterministic
## state transition, not a command and it consumes no RNG.
func advance_red_cliff_phase(at_tick: int) -> bool:
	if status != STATUS_ACTIVE or combat_phase != 1 or at_tick <= started_tick:
		return false
	combat_phase = 2
	phase_advanced_tick = at_tick
	phase_ended_ticks[1] = at_tick
	phase_started_tick = at_tick
	return true


## Apply exactly the current phase and expose only the next sequential phase.
## Campaign owns arithmetic; ActiveBattle owns state-machine invariants.
func apply_red_cliff_phase_outcome(at_tick: int, outcome: Dictionary) -> bool:
	if status != STATUS_ACTIVE or combat_phase < 1 or combat_phase > 5:
		return false
	if phase_results.size() >= combat_phase or at_tick < phase_started_tick:
		return false
	for key in ["attacker_loss", "defender_loss", "attacker_morale_delta", "defender_morale_delta", "schemes"]:
		if not outcome.has(key):
			return false
	var record := outcome.duplicate(true)
	record["phase"] = combat_phase
	record["started_tick"] = phase_started_tick
	record["ended_tick"] = at_tick
	attacker_ships = maxi(0, attacker_ships - maxi(0, int(record["attacker_loss"])))
	defender_ships = maxi(0, defender_ships - maxi(0, int(record["defender_loss"])))
	attacker_morale = clampi(attacker_morale + int(record["attacker_morale_delta"]), 0, Battle.MORALE_MAX)
	defender_morale = clampi(defender_morale + int(record["defender_morale_delta"]), 0, Battle.MORALE_MAX)
	record["attacker_ships_after"] = attacker_ships
	record["defender_ships_after"] = defender_ships
	record["attacker_morale_after"] = attacker_morale
	record["defender_morale_after"] = defender_morale
	phase_results.append(record)
	phase_ended_ticks[combat_phase] = at_tick
	for scheme in record["schemes"]:
		applied_schemes.append(scheme.duplicate(true))
	# A destroyed or broken side is recorded in this phase, but DEMO-RC keeps the
	# fixed five-phase presentation: resolution occurs only in phase five.
	record["attacker_collapsed"] = attacker_ships <= 0 or attacker_morale <= 0
	record["defender_collapsed"] = defender_ships <= 0 or defender_morale <= 0
	if combat_phase == 5:
		var attacker_score := attacker_ships * 1000 + attacker_morale * 10
		var defender_score := defender_ships * 1000 + defender_morale * 10
		_resolve_calculated("cao_side" if attacker_score >= defender_score else "sun_liu_side", at_tick, "phase_five_complete")
		return true
	combat_phase += 1
	phase_advanced_tick = at_tick
	phase_started_tick = at_tick
	return true


func record_player_command(kind: String, seq: int, at_tick: int) -> void:
	player_commands.append({"kind": kind, "seq": seq, "tick": at_tick})


func record_ai_decision(phase: int, decision: String, at_tick: int) -> void:
	ai_decisions.append({"phase": phase, "decision": decision, "tick": at_tick})


func _resolve_calculated(winner_faction_id: String, at_tick: int, reason: String) -> void:
	result = {"winner_faction_id": winner_faction_id, "reason": reason,
		"attacker_ships": attacker_ships, "defender_ships": defender_ships,
		"attacker_morale": attacker_morale, "defender_morale": defender_morale}
	result_applied = true
	resolved_tick = at_tick
	entry_available = false
	status = STATUS_RESOLVED


func resolve_red_cliff(winner_faction_id: String, at_tick: int) -> bool:
	# Kept only for source compatibility: winner selection is no longer an input.
	return false


## Ordered scalar values only: Campaign.digest owns the hash and avoids Dictionary order.
func digest_values() -> Array:
	var values: Array = [
		Rng._hash_string(battle_id),
		Rng._hash_string(cause_event_id),
		Rng._hash_string(scenario_id),
		Rng._hash_string(status),
		Rng._hash_string(region_id),
		Rng._hash_string(system_id),
		Rng._hash_string(anchor_body_id),
		created_tick,
		started_tick,
		campaign_stage,
		combat_phase,
		phase_advanced_tick,
		resolved_tick,
		1 if result_applied else 0,
		Rng._hash_string(String(result.get("winner_faction_id", ""))),
		cancelled_tick,
		Rng._hash_string(cancellation_reason),
		Rng._hash_string(rng_anchor),
		Rng._hash_string(attacker_faction_id),
		Rng._hash_string(defender_faction_id),
		attacker_fleet_ids.size(),
		defender_fleet_ids.size(),
		participant_roles.size(),
		Rng._hash_string(liu_contingent_id),
		1 if entry_available else 0,
		phase_started_tick,
		attacker_ships,
		defender_ships,
		attacker_morale,
		defender_morale,
		Rng._hash_string(attacker_formation_id),
		Rng._hash_string(defender_formation_id),
		phase_results.size(),
		applied_schemes.size(),
		player_commands.size(),
		ai_decisions.size(),
		1 if ai_delegated else 0,
		1 if campaign_result_applied else 0,
	]
	for phase in range(1, 6):
		values.append(int(phase_ended_ticks.get(phase, -1)))
	for record in phase_results:
		for key in ["phase", "started_tick", "ended_tick", "attacker_loss", "defender_loss",
			"attacker_morale_delta", "defender_morale_delta", "attacker_ships_after",
			"defender_ships_after", "attacker_morale_after", "defender_morale_after"]:
			values.append(int(record.get(key, -1)))
	for scheme in applied_schemes:
		values.append(int(scheme.get("phase", -1)))
		values.append(int(scheme.get("kind", -1)))
		values.append(Rng._hash_string(String(scheme.get("caster", ""))))
	for fleet_id in attacker_fleet_ids:
		values.append(Rng._hash_string(fleet_id))
	for fleet_id in defender_fleet_ids:
		values.append(Rng._hash_string(fleet_id))
	var role_ids: Array = participant_roles.keys()
	role_ids.sort()
	for fleet_id in role_ids:
		values.append(Rng._hash_string(String(fleet_id)))
		values.append(Rng._hash_string(String(participant_roles[fleet_id])))
	return values
