extends SceneTree
## Session-only host-computed finish/DNF standings; career rewards are not paid.
const Standings = preload("res://scripts/network/online_race_standings.gd")
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)
func _run() -> void:
	var players := {
		1: {"name":"Host","status":"finished","ms":21000},
		7: {"name":"Guest","status":"finished","ms":23800}}
	var finishes := [
		{"id":1,"name":"Host","ms":21000},
		{"id":7,"name":"Guest","ms":23800}]
	var standings: Dictionary = Standings.settle({}, players, finishes, "drag", 1)
	check("first_approved_finish_earns_ten_session_points",
		int(standings[1].get("points",0))==10 and
		int(standings[1].get("wins",0))==1)
	check("second_approved_finish_earns_seven_session_points",
		int(standings[7].get("points",0))==7 and
		int(standings[7].get("finishes",0))==1)
	check("valid_finishes_save_own_track_personal_best_in_memory",
		int(standings[1].get("best_ms",{}).get("drag",0))==21000)
	check("repeated_host_result_cannot_award_again",
		Standings.settle(standings,players,finishes,"drag",1)==standings)
	check("session_scores_only_not_cash_or_xp",
		not standings[1].has("cash") and not standings[1].has("player_xp") and
		not standings[1].has("car_xp"))
	var partial := players.duplicate(true)
	partial[7]["status"]="racing"
	check("unsettled_race_cannot_credit_anybody",
		Standings.settle(standings,partial,finishes,"circuit",2)==standings)
	var forged := [{"id":999,"name":"Forge","ms":18000}]
	check("unknown_driver_cannot_steal_points",
		Standings.settle(standings,players,forged,"street",2)==standings)
	var second := {
		1: {"name":"Host","status":"dnf","ms":0},
		7: {"name":"Guest","status":"finished","ms":91000}}
	var second_results := [{"id":7,"name":"Guest","ms":91000}]
	standings = Standings.settle(standings,second,second_results,"street",2)
	check("dnf_is_recorded_without_points",
		int(standings[1].get("dnfs",0))==1 and
		int(standings[1].get("points",0))==10)
	check("street_winner_earns_ten_points_and_new_track_best",
		int(standings[7].get("points",0))==17 and
		int(standings[7].get("best_ms",{}).get("street",0))==91000)
	var ranked: Array = Standings.ranked(standings)
	check("ranked_session_board_has_winner_first",
		ranked.size()==2 and int(ranked[0].get("id",0))==7)
	check("race_points_never_exceed_four_player_reward_table",
		Standings.points_for_finish(1)==10 and
		Standings.points_for_finish(4)==3 and
		Standings.points_for_finish(5)==0)
	print("FRIEND SESSION STANDINGS: %s" % (
		"PASS" if failures.is_empty() else "FAIL "+str(failures)))
	quit(0 if failures.is_empty() else 1)
