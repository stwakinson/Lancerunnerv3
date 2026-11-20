extends SceneTree

const State = preload("res://scripts/benchmark/landing_market_state.gd")
var failures := 0
var capture_dir := ""
var test_save := "user://market_smoke_%d.json" % Time.get_ticks_usec()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _state_checks() -> void:
	var state := State.new()
	state.save_path = test_save
	check(state.trade("grain", 2, true).is_empty(), "Commodity purchase must succeed")
	check(state.credits == 7420 and state.owned("grain") == 5 and state.stock.grain == 88, "Buying must update all balances")
	check(state.trade("grain", 2, false).is_empty(), "Commodity sale must succeed")
	check(state.credits == 7484 and state.owned("grain") == 3 and state.stock.grain == 90, "Selling must apply the dealer's sell price")
	var snapshot := JSON.stringify([state.credits, state.cargo, state.stock])
	check(not state.trade("grain", 99, true).is_empty(), "Cargo overflow must be rejected")
	check(not state.trade("missile_rack", 4, true).is_empty(), "Dealer stock must limit purchases")
	check(not state.trade("unknown", 1, true).is_empty() and not state.trade("grain", -1, true).is_empty(), "Invalid trades must be rejected")
	check(snapshot == JSON.stringify([state.credits, state.cargo, state.stock]), "Failed trades must not mutate balances")
	state.credits = 0
	check(not state.trade("alloy", 1, true).is_empty(), "Insufficient funds must be rejected")
	state.credits = 7484
	check(not state.trade("medicine", 1, false).is_empty(), "Cannot sell unowned cargo")
	check(not state.trade("pulse_laser", 1, false).is_empty(), "Fitted gear must not be sold from the locker")
	check(state.trade("cargo_expander", 1, true).is_empty() and state.fit("cargo_expander").is_empty(), "Bought utility must fit")
	check(state.capacity() == 30, "Cargo utility must expand the hold")
	check(state.trade("grain", 21, true).is_empty() and state.cargo_used() == 25, "Expanded cargo space must be usable")
	check(not state.unmount(2).is_empty() and state.capacity() == 30, "Removing a loaded expander must be rejected")
	state.trade("grain", 5, false)
	check(state.unmount(2).is_empty() and state.capacity() == 20, "Expander must unmount after cargo is reduced")
	state.trade("autocannon", 1, true)
	check(state.fit("autocannon").is_empty() and state.weapons[1] == "autocannon", "Weapon must occupy the free hardpoint")
	state.trade("pulse_laser", 1, true)
	check(not state.fit("pulse_laser").is_empty(), "Full hardpoints must reject fitting")
	check(state.save_state(), "State must save")
	var loaded := State.new()
	loaded.save_path = test_save
	var did_load := loaded.load_state()
	check(did_load and loaded.credits == state.credits and loaded.weapons == state.weapons and loaded.cargo == state.cargo and loaded.stock == state.stock, "Save round trip must retain purchases and fittings")
	var corrupt := FileAccess.open(test_save, FileAccess.WRITE)
	corrupt.store_string('{"version":1,"credits":-5}')
	corrupt.close()
	loaded = State.new()
	loaded.save_path = test_save
	check(not loaded.load_state() and loaded.credits == 7500, "Malformed save must not partially overwrite defaults")


func _run() -> void:
	_state_checks()
	if DisplayServer.get_name() == "headless":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
		if failures == 0: print("PASS: market transactions, cargo/fitting limits and save validation")
		quit(0 if failures == 0 else 1)
		return
	var scene: Control = load("res://scenes/benchmark/artois_visual.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	var state := State.new()
	state.save_path = test_save
	scene.market_state = state
	scene.shop_panel.configure(state)
	while root.get_node("SceneFader").busy: await process_frame
	await scene.toggle_docking()
	scene.landing_world.advance(0.6, Vector2.ONE, 1.0)
	scene._sync_shop_hotspots()
	await scene._capture(capture_dir, "market-fronts.png")
	await _click(scene.shop_hotspots.buttons[0])
	check(scene.shop_panel.visible and scene.shop_panel.shop_kind == "commodities", "Clicking the panned commodity shop must open its panel")
	if not scene.shop_panel.visible:
		quit(1)
		return
	var camera: Vector2 = scene.landing_world.camera_position
	var elapsed: float = scene.landing_world.elapsed
	scene.set_process(true)
	await create_timer(0.1).timeout
	check(scene.landing_world.camera_position == camera and scene.landing_world.elapsed > elapsed, "Shop must freeze camera while keeping ambience alive")
	scene.set_process(false)
	await scene.toggle_docking()
	check(scene.landed and scene.shop_panel.visible, "Shop must prevent accidental launch")
	scene.shop_panel._quantity.value = 2
	await process_frame
	scene.shop_panel._quantity.get_line_edit().grab_focus()
	scene.shop_panel._quantity.get_line_edit().text = "2"
	for pressed in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.physical_keycode = KEY_ENTER
		enter.pressed = pressed
		Input.parse_input_event(enter)
	Input.flush_buffered_events()
	await process_frame
	check(scene.landed and scene.shop_panel.visible, "Enter in quantity input must not launch or dismiss the shop")
	scene.shop_panel._buy.pressed.emit()
	check(state.credits == 7420 and state.owned("grain") == 5, "Commodity panel must execute its selected trade")
	await scene._capture(capture_dir, "market-commodities.png")
	await _escape()
	check(not scene.shop_panel.visible and scene.landed and current_scene == scene, "Esc must close the shop before navigation")
	await _click(scene.shop_hotspots.buttons[1])
	check(scene.shop_panel.visible and scene.shop_panel.shop_kind == "equipment", "Outfitter artwork must open the equipment panel")
	scene.shop_panel._buy.pressed.emit()
	scene.shop_panel._fit.pressed.emit()
	check(state.weapons[1] == "pulse_laser" and state.owned("pulse_laser") == 0, "Outfitter must buy and fit a weapon")
	await scene._capture(capture_dir, "market-outfitter.png")
	scene.shop_panel._slots[1].pressed.emit()
	check(state.weapons[1] == "" and state.owned("pulse_laser") == 1, "Slot button must unmount gear into the locker")
	scene.shop_panel._sell.pressed.emit()
	check(state.owned("pulse_laser") == 0, "Unfitted gear must be sellable")
	await _escape()
	root.size = Vector2i(1000, 800)
	await process_frame
	await process_frame
	scene._sync_shop_hotspots()
	await scene._capture(capture_dir, "market-narrow-before.png")
	await _click(scene._commodity_service)
	check(scene.shop_panel.visible and scene.shop_panel.shop_kind == "commodities", "Fixed service buttons must work in narrow windows")
	await scene._capture(capture_dir, "market-narrow-panel.png")
	if not scene.shop_panel.visible:
		quit(1)
		return
	await _escape()
	await _click(scene.shop_hotspots.buttons[1])
	check(scene.shop_panel.visible and scene.shop_panel.shop_kind == "equipment", "Cropped-view hit testing must follow KEEP_ASPECT_COVERED")
	await _escape()
	await scene.toggle_docking()
	check(not scene.landed and not scene.shop_hotspots.visible, "Shops must disappear after launch")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save + ".tmp"))
	if failures == 0: print("PASS: market transactions, fitting, save validation, world clicks, modal input and responsive shop access")
	quit(0 if failures == 0 else 1)


func _click(button: Control) -> void:
	var at := root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await process_frame


func _escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
