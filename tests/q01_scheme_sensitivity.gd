extends SceneTree

## Q-01-02 fixed-seed parameter probe.
##
## This intentionally changes no core constant.  Every mode reuses the M0 seed
## cohort (1000..1099), changing only Campaign.hb_milli, so the result is a
## paired comparison that can be repeated before choosing a ruleset edit.

const RUNS := 100
const PROTAGONISTS: Array[String] = ["조조", "손권", "유종"]
const MODES: Array = [
	[0, "HB 0.00"],
	[100, "HB 0.10"],
	[150, "HB 0.15"],
	[200, "HB 0.20"],
	[250, "HB 0.25 (standard)"],
]


func _init() -> void:
	var data := GameData.load_all()
	print("Q-01-02 fixed-seed HB sensitivity — seeds 1000..1099")
	print("mode                  hist  early  cao   sun   liu spread  events")
	for mode in MODES:
		var historical := 0
		var early := 0
		var wins := {"조조": 0, "손권": 0, "유종": 0}
		var fired := {}
		for run in RUNS:
			var campaign := Campaign.scenario_03(data, 1000 + run)
			campaign.hb_milli = int(mode[0])
			campaign.run_to_end()
			if campaign.historical_outcome():
				historical += 1
			if campaign.end_reason == "조기 종료":
				early += 1
			for faction in PROTAGONISTS:
				if campaign.achieved(faction):
					wins[faction] = int(wins[faction]) + 1
			for event_id in campaign.events_fired:
				fired[event_id] = int(fired.get(event_id, 0)) + int(campaign.events_fired[event_id])
		var rates: Array[int] = [int(wins["조조"]), int(wins["손권"]), int(wins["유종"])]
		rates.sort()
		var spread := INF if rates[0] == 0 else float(rates[2]) / float(rates[0])
		print("%-20s %4.1f%% %4.1f%% %4.1f%% %4.1f%% %4.1f%%  %4.1fx  %2d/17" % [
			String(mode[1]), historical, early, wins["조조"], wins["손권"], wins["유종"], spread, fired.size()])
	quit(0)
