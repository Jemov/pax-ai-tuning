extends Node
## Live node adapter; all native script references come from the active form.
## Never preloads/replaces native scenes and never persists form credentials.
const AdvancedPanelScript = preload("res://mods/ai_tuning/advanced_panel.gd")
var owner_mod: Node
var panel: PanelContainer
var drafts: Dictionary = {}
var _elapsed := 0.0
var _launcher: Node
var _form: Dictionary = {}
var _auto_open := false

func setup(owner: Node) -> void:
	owner_mod = owner; name = "AiTuningLauncherAdapter"
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh.call_deferred()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5: return
	_elapsed = 0.0; refresh()

static func _property(object: Object, key: String) -> bool:
	if not is_instance_valid(object): return false
	for row: Dictionary in object.get_property_list():
		if row.get("name") == key: return true
	return false

func _scene() -> Node:
	if not is_inside_tree(): return null
	var scene: Node = get_tree().current_scene
	if not is_instance_valid(scene) or scene.is_queued_for_deletion(): return null
	for key: String in ["page_m","ai_path","region"]:
		if not _property(scene,key): return null
	return scene

func _native_ai(scene: Node) -> Script:
	var script: Variant = scene.get_script()
	if not script is Script: return null
	var ai: Variant = script.get_script_constant_map().get("LauncherAiScript")
	return ai if ai is Script else null

func _clouds(scene: Node) -> Array:
	var ai: Script = _native_ai(scene)
	if ai == null or not ai.has_method("clouds_for"): return []
	var language := "ru"
	if _property(scene,"lang_"):
		var lang: Variant = scene.get("lang_")
		if lang is Object and _property(lang,"code"): language = str(lang.get("code"))
	var rows: Variant = ai.call("clouds_for",language)
	return rows if rows is Array else []

func _sheet(scene: Node) -> VBoxContainer:
	var region: Variant = scene.get("region")
	if not region is Control or not is_instance_valid(region): return null
	var found: VBoxContainer
	for child: Node in region.get_children():
		if child.is_queued_for_deletion() or not child is ScrollContainer: continue
		for content: Node in child.get_children():
			if content is VBoxContainer and not content.is_queued_for_deletion():
				if found != null: return null
				found = content
	return found

func _find_form(sheet: VBoxContainer, scene: Node) -> Dictionary:
	var services: Array = _clouds(scene)
	for card: Node in sheet.get_children():
		if card == panel or card.is_queued_for_deletion() or not card is PanelContainer: continue
		if card.get_child_count() != 1 or not card.get_child(0) is VBoxContainer: continue
		var body: VBoxContainer = card.get_child(0)
		var model: LineEdit
		var service: OptionButton
		var base_field: LineEdit
		var key_field: LineEdit
		var catalog_field: LineEdit
		for row: Node in body.get_children():
			if row is LineEdit:
				if row.secret:
					if key_field != null: return {}
					key_field = row # Object only; read text solely on explicit capability request.
				elif model == null and base_field == null: base_field = row
				elif model != null: catalog_field = row
			if not row is HBoxContainer: continue
			var option: OptionButton
			var edit: LineEdit
			for item: Node in row.get_children():
				if item is OptionButton: option = item
				elif item is LineEdit and not item.secret: edit = item
			if option != null and edit != null:
				if model != null: return {}
				model = edit
			elif option != null and option.item_count == services.size() and not services.is_empty(): service = option
		if model != null and service != null and base_field != null:
			return {"card":card,"model":model,"service":service,"base":base_field,"key":key_field,"catalog":catalog_field,"services":services}
	return {}

func _target(scene: Node, form: Dictionary) -> Dictionary:
	if not form.is_empty():
		var index: int = form.service.selected
		if index >= 0 and index < form.services.size() and form.services[index] is Dictionary:
			var service: Dictionary = form.services[index]
			var base: String = form.base.text.strip_edges() if service.get("id") == "own" else str(service.get("base","")).strip_edges()
			var model: String = form.model.text.strip_edges()
			if service.get("id") == "yandex" and is_instance_valid(form.catalog):
				var ai: Script = _native_ai(scene)
				var native: Variant = ai.get_script_constant_map().get("RussianProvidersScript") if ai != null else null
				if native is Script and native.has_method("yandex_model"): model = str(native.call("yandex_model",model,form.catalog.text))
			if base != "" and model != "": return {"base":base,"model":model,"label":"Выбранная модель"}
	# Read only these two connected identity fields; never copy or inspect keys.
	if _property(scene,"settings_m"):
		var settings: Variant = scene.get("settings_m")
		if settings is Dictionary:
			var providers: Variant = settings.get("providers")
			var brain: Variant = providers.get("brain") if providers is Dictionary else null
			if brain is Dictionary and brain.get("base") is String and brain.get("model") is String:
				return {"base":brain.base,"model":brain.model,"label":"Подключённая модель"}
	return {"base":"","model":"","label":"Выбранная модель"}

func refresh() -> void:
	var scene: Node = _scene()
	if scene == null or scene.get("page_m") != "нейросеть" or scene.get("ai_path") != "cloud":
		_remove_panel(); return
	var sheet: VBoxContainer = _sheet(scene)
	if sheet == null: _remove_panel(); return
	if is_instance_valid(panel) and panel.get_parent() != sheet: _remove_panel()
	_launcher = scene
	_form = _find_form(sheet,scene)
	if not is_instance_valid(panel):
		panel = AdvancedPanelScript.new(); panel.drafts = drafts
		var native_card: PanelContainer = _form.get("card")
		if native_card == null:
			for child: Node in sheet.get_children():
				if child is PanelContainer and not child.is_queued_for_deletion(): native_card = child; break
		panel.setup(owner_mod,scene,native_card)
		panel.capabilities_requested.connect(_request_capabilities)
		sheet.add_child(panel)
		if not _form.is_empty(): sheet.move_child(panel,_form.card.get_index()+1)
		else:
			# A changed native form still gets a clear connected-model fallback.
			var at := 0
			for child: Node in sheet.get_children():
				if child != panel and child is PanelContainer: at = child.get_index()+1; break
			sheet.move_child(panel,at)
	var target: Dictionary = _target(scene,_form)
	panel.set_target(target.base,target.model,target.label)
	panel.refresh()
	if _auto_open: _auto_open = false; panel.open()

func _request_capabilities(base: String, model: String) -> void:
	if base == "" or model == "" or not is_instance_valid(owner_mod): return
	var query: Array = []
	if is_instance_valid(_launcher) and not _form.is_empty():
		var current: Dictionary = _target(_launcher,_form)
		var ai: Script = _native_ai(_launcher)
		if current.label == "Выбранная модель" and current.base == base and current.model == model and ai != null and ai.has_method("check_request"):
			var key := ""
			if is_instance_valid(_form.get("key")): key = _form.key.text.strip_edges()
			var index: int = _form.service.selected
			if key == "" and index >= 0 and index < _form.services.size(): key = str(_form.services[index].get("without_key",""))
			var built: Variant = ai.call("check_request",base,key,model)
			if built is Array: query = built
			key = ""
	# Native check_request only constructs a packet. The owner performs GET metadata.
	owner_mod.request_capabilities(base,model,query)
	query.clear()
	if is_instance_valid(panel): panel.refresh()

func open() -> void:
	_auto_open = true
	var scene: Node = _scene()
	if scene != null and scene.has_method("_open"):
		scene.set("ai_path","cloud")
		scene.call("_open","нейросеть")
	refresh.call_deferred()

func _remove_panel() -> void:
	if is_instance_valid(panel):
		if panel.get_parent() != null: panel.get_parent().remove_child(panel)
		panel.queue_free()
	panel = null; _form.clear(); _launcher = null

func dispose() -> void:
	set_process(false); _remove_panel()

func _exit_tree() -> void: _remove_panel()
