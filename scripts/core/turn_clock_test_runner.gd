extends SceneTree


func _initialize() -> void:
	var clock_script: Script = load("res://scripts/core/turn_clock.gd")
	var clock: TurnClock = clock_script.new()
	if clock.turn != 1 or not clock.player_active:
		push_error("TurnClock: expected turn 1 player, got %s" % clock.status_text())
		quit(1)
		return
	if clock.status_text() != "第 1 回合 · 玩家行动":
		push_error("TurnClock: bad initial label %s" % clock.status_text())
		quit(1)
		return
	clock.end_turn()
	if clock.turn != 1 or clock.player_active:
		push_error("TurnClock: expected rival still on turn 1, got %s" % clock.status_text())
		quit(1)
		return
	if clock.status_text() != "第 1 回合 · 对手行动":
		push_error("TurnClock: bad rival label %s" % clock.status_text())
		quit(1)
		return
	clock.end_turn()
	if clock.turn != 2 or not clock.player_active:
		push_error("TurnClock: expected turn 2 player, got %s" % clock.status_text())
		quit(1)
		return
	if clock.status_text() != "第 2 回合 · 玩家行动":
		push_error("TurnClock: bad next-round label %s" % clock.status_text())
		quit(1)
		return
	print("TURN_CLOCK_OK %s" % clock.status_text())
	quit(0)
