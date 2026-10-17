extends Node
## Demonstration adapter for the native Settings → AI page. No menu items or modal.
const AdvancedPanelScript = preload("res://mods/ai_tuning/src/ui/advanced_panel.gd")
var owner_mod: Node
var api: Node
var panel: PanelContainer
var scroll: ScrollContainer
var drafts: Dictionary = {}
var _game_ref: WeakRef
var _elapsed := 0.0

func setup(owner: Node, public_api: Node) -> void:
	owner_mod = owner; api = public_api; name = "AiTuningGameUi"
	process_mode = Node.PROCESS_MODE_ALWAYS

func world_ready(game: RefCounted) -> void:
	_remove_panel()
	_game_ref = weakref(game) if is_instance_valid(game) else null
	refresh()

static func _read(value: Variant, key: String) -> Variant:
	if not value is Object or not is_instance_valid(value): return null
	for property: Dictionary in value.get_property_list():
		if property.get("name") == key: return value.get(key)
	return null

func _game() -> Object:
	if is_instance_valid(api):
		for property: Dictionary in api.get_property_list():
			if property.get("name") == "game":
				var current: Variant = api.get("game")
				return current if current is Object and is_instance_valid(current) else null
	return _game_ref.get_ref() if _game_ref != null else null

func _menu() -> Node:
	var game: Object = _game()
	if game == null: return null
	var main: Variant = _read(game,"main")
	if not main is Node and is_instance_valid(owner_mod) and owner_mod.has_method("_world_main"): main = owner_mod.call("_world_main")
	var menu: Variant = _read(_read(main,"ui"),"menu_node")
	return menu if menu is Node and is_instance_valid(menu) and not menu.is_queued_for_deletion() else null

func _settings_body(menu: Node) -> VBoxContainer:
	if menu == null or _read(menu,"visible") != true or _read(menu,"settings_tab") != "нейросеть": return null
	var screen: Variant = _read(menu,"screen")
	if not screen is VBoxContainer or not is_instance_valid(screen) or screen.is_queued_for_deletion(): return null
	# settings_tab persists on other screens: require the actual native tab strip.
	var tab_strip := false
	var found: VBoxContainer
	var captions: Array[String] = []
	if menu.has_method("t_"):
		for code: String in ["game","graphics","нейросеть"]:
			captions.append(str(menu.call("t_","вкл_"+code)))
	for child: Node in screen.get_children():
		if child.is_queued_for_deletion(): continue
		if child is HBoxContainer:
			var tabs := 0
			for button: Node in child.get_children():
				if button is Button and not button.is_queued_for_deletion():
					# Native icon styling moves emoji from text into Button.icon.
					var caption: String = button.text.strip_edges()
					if caption in captions or caption.begins_with("🖥") or caption.begins_with("🎨") or caption.begins_with("🧠"): tabs += 1
			if tabs == 3: tab_strip = true
		if child is ScrollContainer:
			for body: Node in child.get_children():
				if body is VBoxContainer and not body.is_queued_for_deletion():
					if found != null: return null
					found = body
	return found if tab_strip else null

func refresh() -> void:
	var menu: Node = _menu()
	var body: VBoxContainer = _settings_body(menu)
	if body == null: _remove_panel(); return
	if is_instance_valid(panel) and (panel.is_queued_for_deletion() or panel.get_parent() != body): _remove_panel()
	if not is_instance_valid(panel):
		var native_card: PanelContainer
		for child: Node in body.get_children():
			if child.is_queued_for_deletion(): continue
			if child is PanelContainer: native_card = child; break
			for candidate: Node in child.find_children("*","PanelContainer",true,false):
				if not candidate.is_queued_for_deletion(): native_card = candidate; break
			if native_card != null: break
		panel = AdvancedPanelScript.new(); panel.drafts = drafts
		panel.setup(owner_mod,menu,native_card)
		panel.capabilities_requested.connect(_request_capabilities)
		body.add_child(panel)
		scroll = body.get_parent() as ScrollContainer
	_update_target()

# Compatibility with older QA callers; never adds a pause-menu button.
func refresh_pause_menu() -> void: refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5: return
	_elapsed = 0.0; refresh()

func open() -> bool:
	var menu: Node = _menu()
	if menu == null or not is_instance_valid(owner_mod) or not menu.has_method("_settings_screen"): return false
	if menu.has_method("to_open"): menu.call("to_open")
	else: menu.set("visible",true)
	if _settings_body(menu) == null: menu.call("_settings_screen","нейросеть")
	refresh()
	if not is_instance_valid(panel): return false
	panel.open()
	_reveal.call_deferred()
	return true

func _reveal() -> void:
	if is_instance_valid(panel) and not panel.is_queued_for_deletion() and is_instance_valid(scroll): scroll.ensure_control_visible(panel._toggle)

func _update_target() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(owner_mod): return
	var selected: Variant = owner_mod.current_selection()
	if not selected is Dictionary: return
	panel.set_target(str(selected.get("base","")),str(selected.get("model","")),"Подключённая модель")
	panel.refresh()

func _request_capabilities(base: String, model: String) -> void:
	if base == "" or model == "" or not is_instance_valid(owner_mod): return
	var known: Dictionary = owner_mod.capabilities_for(base,model)
	if known.is_empty() or known.has("error"): owner_mod.request_capabilities(base,model,[])
	if is_instance_valid(panel): panel.refresh()

func close() -> void:
	if is_instance_valid(panel): panel._set_open(false)

func _remove_panel() -> void:
	if is_instance_valid(panel):
		if panel.get_parent() != null: panel.get_parent().remove_child(panel)
		panel.queue_free()
	panel = null; scroll = null

func dispose() -> void:
	set_process(false); _remove_panel(); _game_ref = null

func _exit_tree() -> void: _remove_panel()
