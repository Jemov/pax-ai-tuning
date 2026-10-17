extends Node
## Shared native owner for the launcher cloud form and the in-game AI settings tab.
const Store = preload("res://src/ai/tuning/GenerationProfile.gd")
const AdvancedPanelScript = preload("res://src/ai/tuning/AdvancedPanel.gd")
const Metadata = preload("res://src/ai/tuning/ModelMetadata.gd")
const PathsScript = preload("res://src/save/Paths.gd")
const LauncherAiScript = preload("res://src/launcher/LauncherAi.gd")
const PaxAiScript = preload("res://src/ai/PaxAi.gd")
signal profiles_changed
var _host: Node
var _menu := false
var _selection: Callable
var _query: Callable
var _panel: PanelContainer
var _metadata: Node
var _metadata_errors: Dictionary = {}
var _elapsed := 0.0

static func attach_launcher(host: Node, parent: VBoxContainer, address: LineEdit, model: LineEdit, choice: OptionButton, services: Array, catalog: LineEdit, key: LineEdit) -> PanelContainer:
	var selected: Callable = func() -> Dictionary:
		if not is_instance_valid(choice) or choice.selected < 0 or choice.selected >= services.size(): return {"base":"","model":""}
		var service: Dictionary = services[choice.selected]
		var base: String = address.text.strip_edges() if service.get("id") == "own" else str(service.get("base",""))
		var selected_model: String = model.text.strip_edges()
		if service.get("id") == "yandex": selected_model = LauncherAiScript.RussianProvidersScript.yandex_model(selected_model,catalog.text)
		return {"base":base,"model":selected_model}
	var query: Callable = func(base: String, selected_model: String) -> Array:
		var actual: Dictionary = selected.call()
		if Store.Identity.key(str(actual.get("base","")),str(actual.get("model",""))) != Store.Identity.key(base,selected_model): return []
		var service: Dictionary = services[choice.selected]
		var supplied: String = key.text.strip_edges()
		if supplied == "": supplied = str(service.get("without_key",""))
		var built: Array = LauncherAiScript.check_request(base,PaxAiScript.real_key(supplied),selected_model)
		supplied = ""
		return built
	var card: PanelContainer = host._card()
	parent.add_child(card)
	return _attach(host,card.get_child(0) as VBoxContainer,selected,query,false)

static func attach_menu(host: Node, parent: VBoxContainer) -> PanelContainer:
	var selected: Callable = func() -> Dictionary:
		var brain: Dictionary = host.provider_("brain")
		return {"base":str(brain.get("base","")),"model":str(brain.get("model",""))}
	var query: Callable = func(base: String, model: String) -> Array:
		var settings: Dictionary = PathsScript.settings()
		var providers: Variant = settings.get("providers")
		var brain: Variant = providers.get("brain") if providers is Dictionary else null
		if not brain is Dictionary or str(brain.get("base","")) != base or str(brain.get("model","")) != model: return []
		return LauncherAiScript.check_request(base,PaxAiScript.real_key(str(brain.get("key",""))),model)
	return _attach(host,parent,selected,query,true)

static func _attach(host: Node, parent: VBoxContainer, selection: Callable, query: Callable, is_menu: bool) -> PanelContainer:
	var owner := new()
	owner._host = host; owner._menu = is_menu; owner._selection = selection; owner._query = query
	parent.add_child(owner)
	owner._metadata = Metadata.new(); owner.add_child(owner._metadata)
	owner._metadata.changed.connect(func(): owner.profiles_changed.emit())
	owner._panel = AdvancedPanelScript.new(); owner._panel.setup(owner,host); parent.add_child(owner._panel)
	owner._panel.capabilities_requested.connect(owner.request_capabilities)
	owner._refresh_target()
	return owner._panel

func profile_for(base: String, model: String) -> Dictionary: return Store.current(base,model)
func save_profile(base: String, model: String, profile: Dictionary) -> Dictionary: return _save(base,model,profile,false)
func reset_profile(base: String, model: String) -> Dictionary: return _save(base,model,{},true)
func _save(base: String, model: String, profile: Dictionary, reset: bool) -> Dictionary:
	if not is_instance_valid(_host): return {"ok":false,"errors":["Native settings screen is closed."]}
	var settings: Dictionary
	if _menu:
		settings = _host.settings
	else: settings = PathsScript.settings()
	var result: Dictionary = Store.update(settings,base,model,profile,reset)
	if not result.ok: return result
	if _menu: _host.save_it()
	else:
		LauncherAiScript.write_settings(settings); _host.settings_m = settings
	profiles_changed.emit()
	return result

func capabilities_for(base: String, model: String) -> Dictionary:
	var key: String = Store.Identity.key(base,model)
	return {"error":_metadata_errors[key]} if _metadata_errors.has(key) else _metadata.info(base,model)

func request_capabilities(base: String, model: String, _unused: Array = []) -> void:
	var key: String = Store.Identity.key(base,model)
	if key == "" or not _query.is_valid(): return
	var settings: Dictionary = PathsScript.settings()
	var proxy: Variant = settings.get("proxy")
	if (proxy is Dictionary and str(proxy.get("mode","off")) != "off") or LauncherAiScript.RussianProvidersScript.gigachat(base):
		_metadata_errors[key] = "metadata_requires_native_transport"; profiles_changed.emit(); return
	_metadata_errors.erase(key)
	var query: Array = _query.call(base,model)
	if query.is_empty():
		_metadata_errors[key] = "metadata_native_query_unavailable"; profiles_changed.emit(); return
	_metadata.request(base,model,query)
	query.clear()

func _refresh_target() -> void:
	if not _selection.is_valid() or not is_instance_valid(_panel): return
	var target: Dictionary = _selection.call()
	_panel.set_target(str(target.get("base","")),str(target.get("model","")),"Выбранная модель")
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25: _elapsed = 0.0; _refresh_target()
func _exit_tree() -> void:
	if is_instance_valid(_metadata): _metadata.cancel_all()
