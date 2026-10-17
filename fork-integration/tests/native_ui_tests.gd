extends SceneTree
const Owner = preload("res://src/ai/tuning/NativeAiTuning.gd")
const Store = preload("res://src/ai/tuning/GenerationProfile.gd")
const Paths = preload("res://src/save/Paths.gd")
const Launcher = preload("res://src/launcher/LauncherAi.gd")
const Host = preload("res://tests/NativeSettingsFixture.gd")
var errors: Array = []
func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Paths.fixture = {"providers":{"brain":{"base":"https://fixture.invalid/v1","model":"Future","key":"OPAQUE","window":16384}},"keep":{"unknown":true}}
	var host := Host.new(); root.add_child(host); host.settings = Paths.settings()
	var retained_brain: Dictionary = host.settings.providers.brain
	var menu := VBoxContainer.new(); root.add_child(menu)
	var panel: PanelContainer = Owner.attach_menu(host,menu)
	var owner: Node = panel.owner_mod
	check(panel.target_model == "Future" and panel._toggle.get_meta("native_fixture",false),"native owner and shared panel use selected brain and native button factory")
	check(panel.capabilities_requested.is_connected(owner.request_capabilities),"explicit metadata button is connected without requesting on open")
	check(Launcher.query_count == 0 and owner._metadata.get_child_count() == 0,"opening native settings makes no metadata or generation requests")
	var saved: Dictionary = owner.save_profile("https://fixture.invalid/v1","Future",{"enabled":true,"vision_input":true,"max_output_tokens":131072})
	check(saved.ok and host.reloads == 0 and host.saves == 1 and Paths.fixture.keep.unknown,"menu updates live native settings without detaching retained callbacks")
	check(Store.current("https://fixture.invalid/v1","Future").vision_input and not Store.current("https://fixture.invalid/v1","Other").vision_input,"native owner persists manual image capability for the exact endpoint/model")
	panel.set_target("https://fixture.invalid/v1","Other"); panel.set_target("https://fixture.invalid/v1","Future")
	check(panel.fields.vision_input.button_pressed,"native shared panel restores saved image-input checkbox")
	retained_brain.model = "New model"; host.save_it()
	check(Paths.fixture.providers.brain.model == "New model" and Paths.fixture.providers.brain.key == "OPAQUE","retained native provider alias saves later model edit and preserves opaque key")
	check(not JSON.stringify(Paths.fixture[Store.SETTING]).contains("OPAQUE"),"native profile section never duplicates connection credentials")
	owner.reset_profile("https://fixture.invalid/v1","Future")
	check(not Store.current("https://fixture.invalid/v1","Future").enabled and not Store.current("https://fixture.invalid/v1","Future").vision_input,"native reset removes only selected profile and image-input permission")
	var address := LineEdit.new(); address.text = "https://first.invalid/v1"; root.add_child(address)
	var model := LineEdit.new(); model.text = "First"; root.add_child(model)
	var choice := OptionButton.new(); choice.add_item("Own"); root.add_child(choice)
	var catalog := LineEdit.new(); root.add_child(catalog)
	var key := LineEdit.new(); key.text = "OPAQUE-NEW"; root.add_child(key)
	var launcher_ui := VBoxContainer.new(); root.add_child(launcher_ui)
	var launcher_panel: PanelContainer = Owner.attach_launcher(host,launcher_ui,address,model,choice,[{"id":"own"}],catalog,key)
	var launcher_owner: Node = launcher_panel.owner_mod
	address.text = "https://second.invalid/v1"; model.text = "Second"
	var stale: Array = launcher_owner._query.call("https://first.invalid/v1","First")
	check(stale.is_empty() and Launcher.query_count == 0,"launcher poll race cannot send new key to previous endpoint/model")
	var current: Array = launcher_owner._query.call(address.text,model.text)
	check(current.size() == 3 and current[0] == "https://second.invalid/v1/chat/completions" and Launcher.query_count == 1,"matching current launcher connection builds native metadata query only when explicitly requested")
	launcher_owner.save_profile(address.text,model.text,{"enabled":true,"temperature":0.4})
	check(host.settings_m.keep.unknown and Store.current(address.text,model.text).temperature == 0.4,"launcher uses native settings writer and reflects saved settings without provider mutation")
	# Bound store size with independently valid identities, no eviction of another model.
	var bounded: Dictionary = {}
	for i in 256: Store.update(bounded,"https://limit.invalid/v1","Model%d" % i,{"enabled":true})
	var overflow: Dictionary = Store.update(bounded,"https://limit.invalid/v1","Overflow",{"enabled":true})
	check(not overflow.ok and bounded[Store.SETTING].size() == 256,"native generation profile count bounded without hidden eviction")
	for node in [host,menu,address,model,choice,catalog,key,launcher_ui]: node.queue_free()
	await process_frame
	print("NATIVE_UI_TESTS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
