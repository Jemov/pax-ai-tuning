extends PaxMod
const L = preload("res://mods/ai_tuning/src/localization/localization.gd")
## Native settings stay opaque. Only public identities and generation preferences persist.
const Policy = preload("res://mods/ai_tuning/src/domain/profile_policy.gd")
const Identity = preload("res://mods/ai_tuning/src/domain/identity.gd")
const Metadata = preload("res://mods/ai_tuning/src/domain/metadata.gd")
signal profiles_changed
var _ui: Node
var _game_ui: Node
var _metadata: Node
var _metadata_errors: Dictionary = {}
var _transport_provider: Node
var _context_signature := ""
var _lease: Dictionary = {}
var _lease_recovered := false
var _local_lease: Dictionary = {}
var _captures: Dictionary = {}
var _timeouts: Array = []
var _elapsed := 0.0

static func _property(value: Object, key: String) -> bool:
	if not is_instance_valid(value): return false
	for item: Dictionary in value.get_property_list():
		if item.get("name") == key: return true
	return false

func _api() -> Node: return get_node_or_null("/root/Pax")
func _scene() -> Node: return get_tree().current_scene if is_inside_tree() else null
func _world_main() -> Node:
	var api: Node = _api()
	if api == null or not _property(api,"game"): return null
	var game: Variant = api.get("game")
	if not game is Object or not is_instance_valid(game) or not _property(game,"main"): return null
	var main: Variant = game.get("main")
	return main if main is Node and is_instance_valid(main) and not main.is_queued_for_deletion() else null

func _provider_node() -> Node:
	var main: Node = _world_main()
	var provider: Variant = main.get("provider") if _property(main,"provider") else null
	return provider if provider is Node and is_instance_valid(provider) and not provider.is_queued_for_deletion() else null

func _harness() -> Node:
	var api: Node = _api()
	if api == null or not api.has_method("get_mod"): return null
	var value: Variant = api.call("get_mod","pax_harness")
	return value if value is Node and is_instance_valid(value) else null

var _localization: Node

func _mod_loaded() -> void:
	L.configure(load_json("data/lang/ru.json",{}),load_json("data/lang/en.json",{}))
	_localization = L.new(); add_child(_localization); _localization.setup(_localization_roots)
	_localization.language_changed.connect(_language_changed)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_metadata = Metadata.new(); add_child(_metadata)
	_metadata.changed.connect(func(): profiles_changed.emit())
	var ui_script: Resource = load_resource("src/ui/launcher_ui.gd")
	if ui_script is Script:
		_ui = ui_script.new(); add_child(_ui); _ui.setup(self)
	_setup_game_ui()
	hook("ai_request",_before_request,100)
	hook("ai_request",_capture_request,-100)
	var api: Node = _api()
	if api != null and api.has_method("register_command"): api.call("register_command","ai_tuning",_command,L.text("ai_tuning open — тонкая настройка выбранной модели"))
	sync_context(); _attach_transport()

func _world_ready(_game: PaxGame) -> void:
	_context_signature = ""; _captures.clear()
	_setup_game_ui()
	if is_instance_valid(_game_ui): _game_ui.world_ready(_game)
	sync_context(); _attach_transport()

func _setup_game_ui() -> void:
	if is_instance_valid(_game_ui): return
	var script: Resource = load_resource("src/ui/game_ui.gd")
	if script is Script:
		_game_ui = script.new(); add_child(_game_ui); _game_ui.setup(self,_api())

## QA/public UI entry: opens connected-model settings in game, launcher otherwise.
func open_settings() -> bool:
	_setup_game_ui()
	if _world_main() != null and is_instance_valid(_game_ui): return _game_ui.open()
	if is_instance_valid(_ui): _ui.open(); return true
	return false

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5: return
	_elapsed = 0.0; sync_context(); _attach_transport()

func _profiles() -> Dictionary:
	var raw: Variant = get_setting("profiles",{})
	var clean: Dictionary = {}
	if not raw is Dictionary: return clean
	for key: Variant in raw:
		var record: Variant = raw[key]
		if not record is Dictionary or not record.get("base") is String or not record.get("model") is String or not record.get("profile") is Dictionary: continue
		if key != Identity.key(record.base,record.model) or key == "": continue
		var checked: Dictionary = Policy.validate(record.profile)
		if checked.ok: clean[key] = {"base":Identity.base_url(record.base),"model":record.model.strip_edges(),"profile":checked.profile}
	return clean

func profile_for(base: String, model: String) -> Dictionary:
	var record: Dictionary = _profiles().get(Identity.key(base,model),{})
	return record.profile.duplicate(true) if not record.is_empty() else Policy.validate({}).profile

func save_profile(base: String, model: String, profile: Dictionary) -> Dictionary:
	var key: String = Identity.key(base,model)
	if key == "": return {"ok":false,"errors":["profile: choose a valid public API address and model."]}
	var checked: Dictionary = Policy.validate(profile)
	if not checked.ok: return {"ok":false,"errors":checked.errors}
	var records: Dictionary = _profiles()
	if records.size() >= 256 and not records.has(key): return {"ok":false,"errors":["profiles: maximum 256 saved profiles; reset an unused profile first."]}
	records[key] = {"base":Identity.base_url(base),"model":model.strip_edges(),"profile":checked.profile}
	set_setting("profiles",records)
	sync_context(); _attach_transport(); profiles_changed.emit()
	return {"ok":true,"errors":[]}

func reset_profile(base: String, model: String) -> Dictionary:
	var key: String = Identity.key(base,model)
	if key == "": return {"ok":false,"errors":["profile: choose a valid public API address and model."]}
	var records: Dictionary = _profiles(); records.erase(key); set_setting("profiles",records)
	sync_context(); _attach_transport(); profiles_changed.emit()
	return {"ok":true,"errors":[]}

static func _constants(value: Object) -> Dictionary:
	var script: Variant = value.get_script() if is_instance_valid(value) else null
	return script.get_script_constant_map() if script is Script else {}

func _host() -> Dictionary:
	var main: Node = _world_main()
	var ui: Variant = main.get("ui") if _property(main,"ui") else null
	var menu: Variant = ui.get("menu_node") if ui is Object and _property(ui,"menu_node") else null
	if menu is Node and is_instance_valid(menu) and _property(menu,"settings") and menu.has_method("_load_it") and menu.has_method("provider_") and menu.has_method("save_it"):
		return {"kind":"world","node":menu}
	var scene: Node = _scene()
	var constants: Dictionary = _constants(scene)
	var ai: Variant = constants.get("LauncherAiScript")
	if ai is Script and ai.has_method("write_settings") and _property(scene,"settings_m"):
		return {"kind":"launcher","node":scene,"ai":ai}
	return {}

func _refresh_world_settings(menu: Node) -> void:
	# Native form callbacks retain provider dictionaries. Reloading while that
	# menu is open would detach those references and discard subsequent edits.
	if _property(menu,"visible") and bool(menu.get("visible")): return
	menu.call("_load_it")

func _native_state(refresh: bool = false) -> Dictionary:
	var host: Dictionary = _host()
	if host.is_empty(): return {}
	var settings: Variant
	if host.kind == "world":
		if refresh: _refresh_world_settings(host.node)
		settings = host.node.get("settings")
	else: settings = host.node.get("settings_m")
	if not settings is Dictionary: return {}
	var providers: Variant = settings.get("providers")
	var brain: Variant = providers.get("brain") if providers is Dictionary else null
	if not brain is Dictionary: return {}
	var proxy: Variant = settings.get("proxy")
	# Select public scalar fields only. Never retain/copy/log the native settings.
	return {"base":str(brain.get("base","")),"model":str(brain.get("model","")),"mode":str(brain.get("mode","off")),"window":int(brain.get("window",0)),"proxy_mode":str(proxy.get("mode","off")) if proxy is Dictionary else "off"}

func current_selection() -> Dictionary:
	var selected: Dictionary = _native_state()
	if selected.is_empty():
		var provider: Node = _provider_node()
		selected = {"base":str(provider.get("base_url")),"model":str(provider.get("model")),"mode":"native","window":int(provider.call("context_window")) if provider.has_method("context_window") else 0} if provider != null else {"base":"","model":"","mode":"off","window":0}
	selected.erase("proxy_mode")
	selected.base = Identity.base_url(str(selected.get("base","")))
	return selected

func _write_window(value: int, expected: int) -> bool:
	var host: Dictionary = _host()
	if host.is_empty(): return false
	if host.kind == "world":
		_refresh_world_settings(host.node)
		var settings: Variant = host.node.get("settings")
		if not settings is Dictionary or not settings.get("providers") is Dictionary or not settings.providers.get("brain") is Dictionary: return false
		var brain: Variant = host.node.call("provider_","brain")
		if not brain is Dictionary or int(brain.get("window",0)) != expected: return false
		brain["window"] = value
		host.node.call("save_it")
		return true
	# The live native form owns its current settings and the native writer persists it.
	# Never reach into private core settings accessors or retain a stale copy.
	var settings: Variant = host.node.get("settings_m")
	if not settings is Dictionary or not settings.get("providers") is Dictionary or not settings.providers.get("brain") is Dictionary: return false
	if int(settings.providers.brain.get("window",0)) != expected: return false
	settings.providers.brain["window"] = value
	host.ai.call("write_settings",settings)
	host.node.set("settings_m",settings)
	return true

func _release_context() -> void:
	if not _lease.is_empty():
		_write_window(int(_lease.prior),int(_lease.value))
		_lease.clear(); set_setting("context_lease",{})
	if not _local_lease.is_empty():
		var provider: Variant = _local_lease.provider.get_ref()
		if provider is Node and is_instance_valid(provider) and provider.get("local_window") == _local_lease.value: provider.set("local_window",_local_lease.prior)
		_local_lease.clear()

func sync_context(provider: Node = null) -> void:
	var state: Dictionary = _native_state(true)
	if state.is_empty(): return
	if not _lease_recovered:
		var stored: Variant = get_setting("context_lease",{})
		if stored is Dictionary and stored.get("key") is String and stored.key.length() == 64 and Policy._integer(stored.get("prior")) and Policy._integer(stored.get("value"),false): _lease = {"key":stored.key,"prior":int(stored.prior),"value":int(stored.value)}
		_lease_recovered = true
		_release_context()
		state = _native_state(true)
	var key: String = Identity.key(state.base,state.model)
	var profile: Dictionary = profile_for(state.base,state.model)
	var signature: String = key+JSON.stringify(profile).sha256_text()
	if signature == _context_signature: return
	_release_context(); _captures.clear()
	state = _native_state(true)
	_context_signature = signature
	if key == "" or not profile.enabled or profile.context_tokens == 0: return
	var desired: int = int(profile.context_tokens)
	_lease = {"key":key,"prior":int(state.window),"value":desired}
	set_setting("context_lease",_lease)
	if _write_window(desired,int(state.window)): return
	_lease.clear(); set_setting("context_lease",{})
	# A native explicit window outranks local_window, so never pretend a fallback won.
	if state.window != 0: return
	if provider == null: provider = _provider_node()
	if _property(provider,"local_window"):
		_local_lease = {"provider":weakref(provider),"prior":int(provider.get("local_window")),"value":desired}
		provider.set("local_window",desired)

func capabilities_for(base: String, model: String) -> Dictionary:
	var key: String = Identity.key(base,model)
	if _metadata_errors.has(key): return {"error":_metadata_errors[key]}
	return _metadata.info(base,model) if is_instance_valid(_metadata) else {}

func _native_auth(base: String, provider: Node) -> bool:
	var harness: Node = _harness()
	var stock: Variant = _constants(harness).get("StockCompat")
	if stock is Script and stock.has_method("native_auth_transport") and is_instance_valid(provider) and Identity.base_url(str(provider.get("base_url"))) == Identity.base_url(base): return bool(stock.call("native_auth_transport",provider))
	var native: Variant
	if is_instance_valid(provider) and provider.has_method("requests"):
		var builder: Variant = provider.call("requests")
		if builder is Object: native = _constants(builder).get("RussianProvidersScript")
	if not native is Script:
		var ai: Variant = _constants(_scene()).get("LauncherAiScript")
		if ai is Script: native = ai.get_script_constant_map().get("RussianProvidersScript")
	if not native is Script: return false
	for method: Dictionary in native.get_script_method_list():
		if method.get("name") != "gigachat": continue
		var args: Array = method.get("args",[])
		if (int(method.get("flags",0)) & METHOD_FLAG_STATIC) == 0 or args.size() < 1 or args.size()-method.get("default_args",[]).size() > 1: return false
		if int(args[0].get("type",TYPE_NIL)) not in [TYPE_NIL,TYPE_STRING]: return false
		var answer: Variant = native.call("gigachat",base)
		return answer is bool and answer
	return false

func request_capabilities(base: String, model: String, query: Array) -> void:
	var key: String = Identity.key(base,model)
	if key == "" or not is_instance_valid(_metadata): return
	var state: Dictionary = _native_state(true)
	var error := ""
	var provider: Node = _provider_node()
	if state.get("proxy_mode","off") != "off": error = "metadata_native_proxy_required"
	elif _native_auth(base,provider): error = "metadata_native_auth_required"
	elif query.is_empty():
		# The in-game UI has no key field. Let the exact connected native provider
		# construct opaque auth headers; this does not send a generation request.
		if provider != null and provider.has_method("_build_request") and Identity.base_url(str(provider.get("base_url"))) == Identity.base_url(base) and str(provider.get("model")) == model:
			var built: Variant = provider.call("_build_request","JSON","JSON","",0.2,256,"mod_ai_tuning_catalog",true)
			if built is Array: query = built
		if query.is_empty(): error = "metadata_native_query_unavailable"
	if error != "":
		if _metadata_errors.size() >= 32 and not _metadata_errors.has(key): _metadata_errors.erase(_metadata_errors.keys()[0])
		_metadata_errors[key] = error; profiles_changed.emit(); return
	_metadata_errors.erase(key); _metadata.request(base,model,query)

func output_limit(provider: Node, fallback: int, small_request: bool = false) -> int:
	if not is_instance_valid(provider): return fallback
	var output: int = Policy.output_budget(profile_for(str(provider.get("base_url")),str(provider.get("model"))),fallback)
	return mini(output,fallback) if small_request else output

func apply_query(provider: Node, query: Array, reserved_budget: int = 0) -> Dictionary:
	if not is_instance_valid(provider): return {"ok":false,"query":query.duplicate(true),"errors":["provider: unavailable."],"protected_fields":[],"timeout_seconds":0}
	var profile: Dictionary = profile_for(str(provider.get("base_url")),str(provider.get("model")))
	var protected: Array = Policy.protected_generation_fields(profile)
	if profile.enabled and reserved_budget > 0:
		var ceiling: int = Policy.output_budget(profile,reserved_budget)
		profile.max_output_tokens = mini(ceiling,reserved_budget)
		for path: String in Policy._existing(profile.extra,Policy.BUDGET_PATHS): Policy._set(profile.extra,path,profile.max_output_tokens)
		# An extra-only field is also the explicit manual field selection.
		var extra_fields: Array = Policy._existing(profile.extra,Policy.BUDGET_PATHS)
		if profile.token_field == "auto" and extra_fields.size() == 1 and extra_fields[0] in Policy.TOKEN_FIELDS: profile.token_field = extra_fields[0]
	var result: Dictionary = Policy.apply(query,profile)
	result["protected_fields"] = protected
	result["timeout_seconds"] = int(profile.timeout_seconds) if profile.enabled else 0
	return result

func _attach_transport() -> void:
	var provider: Node = _provider_node()
	if is_instance_valid(_transport_provider) and _transport_provider != provider: _detach_transport()
	if provider == null or not _property(provider,"via_network") or not provider.has_method("_build_request") or not provider.has_method("requests"): return
	var active: bool = profile_for(str(provider.get("base_url")),str(provider.get("model"))).enabled
	if _native_state().get("mode","off") == "off": active = false
	if provider.has_method("why_offline") and str(provider.call("why_offline")) != "": active = false
	var route: Variant = provider.get("via_network")
	if route == _network:
		if not active: _detach_transport()
		return
	if not active or not route is Callable or route.is_valid(): return
	var builder: Variant = provider.call("requests")
	if not builder is Object or not builder.has_method("_dispatch_gigachat"): return
	_transport_provider = provider; provider.set("via_network",_network)

func _detach_transport() -> void:
	if is_instance_valid(_transport_provider) and _transport_provider.get("via_network") == _network: _transport_provider.set("via_network",Callable())
	_transport_provider = null; _captures.clear()

func _before_request(data: Dictionary) -> void:
	var provider: Node = _provider_node()
	if provider == null: return
	sync_context(provider); _attach_transport()
	data["max_tokens"] = output_limit(provider,int(data.get("max_tokens",8192)),bool(data.get("small",false)))

func _capture_request(data: Dictionary) -> void:
	var channel: String = str(data.get("channel",""))
	if channel.begins_with("mod_pax_harness_") or data.get("cancel",false) or str(data.get("answer","")) != "": return
	var provider: Node = _provider_node()
	if provider == null or not profile_for(str(provider.get("base_url")),str(provider.get("model"))).enabled: return
	var route: Variant = provider.get("via_network")
	if not route is Callable or not route.is_valid(): return
	# Cooperate only with our own route or the explicitly integrated Harness.
	if route != _network and (route.get_object() != _harness() or route.get_method() != "_network"): return
	if _captures.size() >= 64 and not _captures.has(channel): _captures.erase(_captures.keys()[0])
	_captures[channel] = {"system":str(data.get("system","")),"user":str(data.get("user","")),"dossier":str(data.get("dossier","")),"signature":_context_signature,"provider":provider.get_instance_id(),"time":Time.get_ticks_msec()}

func prepare_native_packet(provider: Node, packet: Dictionary) -> Dictionary:
	var prepared: Dictionary = packet.duplicate(true)
	var channel: String = str(prepared.get("к",""))
	if channel.begins_with("mod_pax_harness_") or not is_instance_valid(provider) or not profile_for(str(provider.get("base_url")),str(provider.get("model"))).enabled:
		return {"ok":true,"packet":prepared,"errors":[]}
	var captured: Dictionary = _captures.get(channel,{})
	_captures.erase(channel)
	if captured.is_empty() or captured.provider != provider.get_instance_id() or captured.signature != _context_signature or Time.get_ticks_msec()-int(captured.time) > 10000:
		return {"ok":false,"packet":prepared,"errors":["Original request before native fitting is unavailable; retry the request."],"code":"ai_tuning_context_source_unavailable"}
	var reserved: int = output_limit(provider,int(prepared.get("pr",8192)),bool(prepared.get("corr",false)))
	var window: int = int(provider.call("context_window")) if provider.has_method("context_window") else 0
	if window <= 0 or ceili(float(str(captured.system).length()+str(captured.user).length()+str(captured.dossier).length())/2.0)+reserved+1024 > window:
		return {"ok":false,"packet":prepared,"errors":["Full input plus reserved output exceeds the actual context window. Increase context or lower output/input; no clipped request was sent."],"code":"context_length_exceeded"}
	prepared["с"] = captured.system; prepared["п"] = captured.user; prepared["д"] = captured.dossier; prepared["pr"] = reserved
	return {"ok":true,"packet":prepared,"errors":[]}

func _set_timeout(destination: HTTPRequest, value: int) -> void:
	set_request_timeout(destination,value)

## Shared with cooperative transports: an override belongs to one request only.
func set_request_timeout(destination: HTTPRequest, value: int) -> void:
	if value <= 0: return
	_timeouts = _timeouts.filter(func(item: Dictionary): return is_instance_valid(item.node.get_ref()))
	for item: Dictionary in _timeouts:
		if item.node.get_ref() == destination:
			if destination.timeout != item.value: item.prior = destination.timeout
			item.value = float(value); destination.timeout = float(value); return
	var callback: Callable = _timeout_finished.bind(weakref(destination))
	_timeouts.append({"node":weakref(destination),"prior":destination.timeout,"value":float(value),"callback":callback})
	destination.timeout = float(value)
	destination.request_completed.connect(callback,CONNECT_ONE_SHOT)

func _timeout_finished(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray, reference: WeakRef) -> void:
	var destination: Variant = reference.get_ref()
	if is_instance_valid(destination): restore_request_timeout(destination)

func restore_request_timeout(destination: HTTPRequest) -> void:
	for index: int in range(_timeouts.size()-1,-1,-1):
		var item: Dictionary = _timeouts[index]
		var node: Variant = item.node.get_ref()
		if not is_instance_valid(node):
			_timeouts.remove_at(index)
		elif node == destination:
			if node.request_completed.is_connected(item.callback): node.request_completed.disconnect(item.callback)
			if node.timeout == item.value: node.timeout = item.prior
			_timeouts.remove_at(index)

func _failure(provider: Node, destination: HTTPRequest, errors: Array, code: String = "ai_tuning_invalid_profile") -> void:
	restore_request_timeout(destination)
	var body: Dictionary = {"error":{"type":"invalid_request_error","code":code,"message":"AI tuning: "+"; ".join(PackedStringArray(errors.slice(0,8))).left(2000)}}
	provider.call_deferred("_curl_answer",destination,400,JSON.stringify(body).to_utf8_buffer())

func _network(destination: HTTPRequest, packet: Dictionary) -> void:
	var provider: Node = _transport_provider
	if not is_instance_valid(provider) or not is_instance_valid(destination): return
	var channel: String = str(packet.get("к",""))
	var system: String = str(packet.get("с","")); var user: String = str(packet.get("п","")); var dossier: String = str(packet.get("д",""))
	var heat: float = float(packet.get("ж",0.2)); var small: bool = bool(packet.get("corr",false))
	var reserved: int = output_limit(provider,int(packet.get("pr",8192)),small)
	if not channel.begins_with("mod_pax_harness_"):
		var captured: Dictionary = _captures.get(channel,{}); _captures.erase(channel)
		if captured.is_empty() or captured.provider != provider.get_instance_id() or captured.signature != _context_signature or Time.get_ticks_msec()-int(captured.time) > 10000:
			_failure(provider,destination,["Original request before native fitting is unavailable; retry the request."],"ai_tuning_context_source_unavailable"); return
		system = captured.system; user = captured.user; dossier = captured.dossier
		var window: int = int(provider.call("context_window")) if provider.has_method("context_window") else 0
		if window <= 0 or ceili(float(system.length()+user.length()+dossier.length())/2.0)+reserved+1024 > window:
			_failure(provider,destination,["Full input plus reserved output exceeds the actual context window. Increase context or lower output/input; no clipped request was sent."],"context_length_exceeded"); return
	var query: Array = provider.call("_build_request",system,user,dossier,heat,reserved,channel,small)
	destination.set_meta("retry_args",[system,user,dossier,heat,reserved,channel,small])
	destination.set_meta("sent_head",user.left(300)); destination.set_meta("sent_at",Time.get_ticks_msec()); destination.set_meta("chars",system.length()+user.length()+dossier.length())
	var harness: Node = _harness()
	if harness != null and harness.has_method("stream_request") and harness.call("stream_request",provider,destination,query,channel): return
	var applied: Dictionary = apply_query(provider,query,reserved)
	if not applied.ok: _failure(provider,destination,applied.errors); return
	query = applied.query; _set_timeout(destination,int(applied.timeout_seconds))
	var raw: String = JSON.stringify(query[2])
	if _property(provider,"dump_folder") and str(provider.get("dump_folder")) != "" and provider.has_method("_to_dump"): provider.call("_to_dump",destination,str(query[0]),raw)
	var sent: bool = bool(provider.call("requests").call("_dispatch_gigachat",destination,raw,query[1],query[0],channel))
	if not sent:
		restore_request_timeout(destination)
		provider.call_deferred("_curl_answer",destination,0,PackedByteArray())

func _command(args: PackedStringArray) -> String:
	if args.is_empty() or args[0] == "open":
		open_settings()
	return JSON.stringify({"selection":current_selection(),"active":is_instance_valid(_transport_provider)})

func _mod_unloaded() -> void:
	if is_instance_valid(_localization): _localization.queue_free()
	_localization = null
	_detach_transport(); _release_context()
	for item: Dictionary in _timeouts.duplicate():
		var destination: Variant = item.node.get_ref()
		if is_instance_valid(destination): restore_request_timeout(destination)
	_timeouts.clear(); _captures.clear()
	if is_instance_valid(_metadata): _metadata.cancel_all(); _metadata.queue_free()
	if is_instance_valid(_ui): _ui.dispose(); _ui.queue_free()
	if is_instance_valid(_game_ui): _game_ui.dispose(); _game_ui.queue_free()
	_game_ui = null
	_ui = null; _metadata = null

func _localization_roots() -> Array:
	return [_ui.panel if is_instance_valid(_ui) else null,_game_ui.panel if is_instance_valid(_game_ui) else null]

func _language_changed() -> void:
	profiles_changed.emit()
