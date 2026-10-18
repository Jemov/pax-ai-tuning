extends PanelContainer
const L = preload("res://mods/ai_tuning/src/localization/localization.gd")
## Per-target generation preferences. No credentials, native settings or I/O.
const Policy = preload("res://mods/ai_tuning/src/domain/profile_policy.gd")
signal capabilities_requested(base: String, model: String)
var owner_mod: Node
var target_base := ""
var target_model := ""
var drafts: Dictionary = {}
var fields: Dictionary = {}
var _body: VBoxContainer
var _target: Label
var _caps: Label
var _errors: Label
var _apply: Button
var _toggle: Button
var _loading := false
var _source_label := L.text("Выбранная модель")
var _native_host: Node

func embed_in_native_form() -> void:
	# The existing native button is the only entry point; this is its form body.
	_toggle.hide()
	_set_open(true)
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())

func setup(owner: Node, native_host: Node = null, native_card: PanelContainer = null) -> void:
	owner_mod = owner; _native_host = native_host
	set_meta("mod_i18n_scope","ai_tuning")
	name = "AiTuningAdvancedPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Native integration may put this body inside SettingsScreen.block.
	# Adapters copy an actual neighbouring native card, never a private palette.
	add_theme_stylebox_override("panel",native_card.get_theme_stylebox("panel") if is_instance_valid(native_card) else StyleBoxEmpty.new())
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",12)
	add_child(column)
	_toggle = _button(L.text("Тонкая настройка")); _toggle.name = "AdvancedToggle"
	_toggle.text = L.text("Тонкая настройка  ▸"); _toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.add_theme_font_size_override("font_size",17)
	_toggle.custom_minimum_size.y = 42
	_toggle.pressed.connect(func(): _set_open(not _body.visible))
	column.add_child(_toggle)
	_target = _label(""); _target.name = "TargetLabel"; column.add_child(_target)
	_target.add_theme_font_size_override("font_size",13)
	_body = VBoxContainer.new(); _body.name = "AdvancedBody"; _body.visible = false
	_body.add_theme_constant_override("separation",12); column.add_child(_body)
	var enabled := CheckBox.new(); enabled.name = "ProfileEnabled"; enabled.text = L.text("Использовать профиль")
	fields.enabled = enabled; _body.add_child(enabled); enabled.toggled.connect(func(_v): _changed())
	var vision := CheckBox.new(); vision.name = "VisionInput"; vision.text = L.text("Изображения на вход")
	fields.vision_input = vision; _body.add_child(vision); vision.toggled.connect(func(_v): _changed())
	_body.add_child(_label(L.text("Разрешает Harness передавать модели снимок игрового окна. Включите профиль; API должен поддерживать изображения.")))
	_caps = _label(""); _caps.name = "CapabilitiesStatus"; _body.add_child(_caps)
	var update := _button(L.text("Обновить возможности")); update.name = "RefreshCapabilities"; update.text = L.text("Обновить возможности")
	update.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	update.pressed.connect(func(): capabilities_requested.emit(target_base,target_model)); _body.add_child(update)
	_input("context_tokens",L.text("Окно контекста, токенов"),L.text("0 — автоматически. Явное значение учитывает реальную ёмкость модели."),"0")
	_input("max_output_tokens",L.text("Максимум ответа, токенов"),L.text("0 — автоматически. Доступный максимум зависит от модели и API."),"0")
	_input("timeout_seconds",L.text("Ожидание ответа, секунд"),L.text("0 — автоматически. Для долгих рассуждений можно увеличить ожидание."),"0")
	_input("reasoning",L.text("Усилие рассуждения"),L.text("Пусто — автоматически. Точное значение API: например none, low, high. Поддержка зависит от модели."),"")
	var choices := OptionButton.new(); choices.name = "ReasoningValues"; choices.fit_to_longest_item = false; choices.clip_text = true
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL; choices.visible = false
	choices.item_selected.connect(func(i):
		if i > 0: fields.reasoning.text = choices.get_item_text(i))
	fields.reasoning_values = choices; _body.add_child(choices)
	_input("verbosity",L.text("Подробность ответа"),L.text("Пусто — автоматически. Используйте точное значение, поддерживаемое API."),"")
	var verbosity_choices := OptionButton.new(); verbosity_choices.name = "VerbosityValues"; verbosity_choices.fit_to_longest_item = false; verbosity_choices.clip_text = true
	verbosity_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL; verbosity_choices.visible = false
	verbosity_choices.item_selected.connect(func(i):
		if i > 0: fields.verbosity.text = verbosity_choices.get_item_text(i))
	fields.verbosity_values = verbosity_choices; _body.add_child(verbosity_choices)
	_optional_number("temperature",L.text("Температура"),L.text("0–2. Меньше — более предсказуемый ответ."))
	_optional_number("top_p","Top-p",L.text("0–1. Доля вероятностной массы при выборе токенов."))
	_choice("token_field",L.text("Поле лимита ответа"),["auto","max_tokens","max_completion_tokens","max_output_tokens"])
	_choice("reasoning_field",L.text("Поле усилия рассуждения"),["auto","reasoning_effort","reasoning.effort"])
	_body.add_child(_label(L.text("Дополнительные параметры JSON")))
	var extra := CodeEdit.new(); extra.name = "ExtraJson"; extra.custom_minimum_size = Vector2(0,150)
	extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL; extra.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	extra.line_folding = true; extra.gutters_draw_line_numbers = true; extra.text = "{}"
	extra.text_changed.connect(_changed); fields.extra = extra; _body.add_child(extra)
	_body.add_child(_label(L.text("Только параметры генерации. Адрес, ключи, модель и сообщения задаёт игра.")))
	_errors = _label(""); _errors.name = "ValidationErrors"; _body.add_child(_errors)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",10); actions.add_theme_constant_override("v_separation",8)
	_apply = _button(L.text("Применить")); _apply.name = "ApplyProfile"; _apply.text = L.text("Применить"); _apply.custom_minimum_size = Vector2(130,40)
	_apply.pressed.connect(_save); actions.add_child(_apply)
	var reset := _button(L.text("Сбросить")); reset.name = "ResetProfile"; reset.text = L.text("Сбросить"); reset.custom_minimum_size = Vector2(130,40)
	reset.pressed.connect(_reset); actions.add_child(reset); _body.add_child(actions)
	if owner_mod.has_signal("profiles_changed"): owner_mod.connect("profiles_changed",refresh)
	set_target("","")

func _button(text: String) -> Button:
	var native: Variant = _native_host.call("_button",text) if is_instance_valid(_native_host) and _native_host.has_method("_button") else null
	var button: Button = native if native is Button else Button.new()
	button.text = text
	return button

func _label(text: String) -> Label:
	var native: Variant = _native_host.call("_text",text) if is_instance_valid(_native_host) and _native_host.has_method("_text") else null
	var label: Label = native if native is Label else Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",14)
	return label

func _input(key: String, title: String, hint: String, placeholder: String) -> void:
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",5)
	box.add_child(_label(title))
	var edit := LineEdit.new(); edit.name = key; edit.placeholder_text = placeholder
	edit.max_length = 80
	edit.custom_minimum_size.y = 36; edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(_v): _changed()); fields[key] = edit; box.add_child(edit)
	var explanation := _label(hint)
	explanation.add_theme_font_size_override("font_size",12)
	box.add_child(explanation); _body.add_child(box)

func _optional_number(key: String, title: String, hint: String) -> void:
	_input(key,title,hint,"")
	var automatic := CheckBox.new(); automatic.name = key+"_auto"; automatic.text = L.text("Автоматически"); automatic.button_pressed = true
	automatic.toggled.connect(func(on): fields[key].editable = not on; _changed())
	fields[key+"_auto"] = automatic; _body.add_child(automatic)

func _choice(key: String, title: String, values: Array) -> void:
	_body.add_child(_label(title))
	var selector := OptionButton.new(); selector.name = key; selector.fit_to_longest_item = false; selector.clip_text = true
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL; selector.custom_minimum_size.y = 36
	for value: String in values: selector.add_item(L.text("Автоматически") if value == "auto" else value); selector.set_item_metadata(selector.item_count-1,value)
	selector.item_selected.connect(func(_i): _changed()); fields[key] = selector; _body.add_child(selector)

func _key() -> String: return JSON.stringify([target_base,target_model])

func set_target(base: String, model: String, source_label: String = "Выбранная модель") -> void:
	_source_label = source_label
	if target_base == base and target_model == model and not fields.is_empty() and fields.context_tokens.text != "":
		_target.text = source_label+": "+model+"\n"+base
		return
	target_base = base; target_model = model
	_target.text = source_label+": "+model+"\n"+base if base != "" and model != "" else L.text("Выберите модель в форме подключения.")
	var profile: Dictionary = owner_mod.profile_for(base,model) if base != "" and model != "" else {}
	_load_profile(profile)
	if drafts.has(_key()): _load_draft(drafts[_key()])
	refresh()

func _load_profile(profile: Dictionary) -> void:
	_loading = true
	fields.enabled.button_pressed = bool(profile.get("enabled",false))
	fields.vision_input.button_pressed = bool(profile.get("vision_input",false))
	for key: String in ["context_tokens","max_output_tokens","timeout_seconds"]: fields[key].text = str(profile.get(key,0))
	for key: String in ["reasoning","verbosity"]: fields[key].text = str(profile.get(key,""))
	for key: String in ["temperature","top_p"]:
		fields[key+"_auto"].button_pressed = profile.get(key) == null
		fields[key].editable = profile.get(key) != null
		fields[key].text = "" if profile.get(key) == null else str(profile[key])
	for key: String in ["token_field","reasoning_field"]:
		var selector: OptionButton = fields[key]
		for i: int in selector.item_count:
			if selector.get_item_metadata(i) == profile.get(key,"auto"): selector.select(i)
	fields.extra.text = JSON.stringify(profile.get("extra",{}),"  ")
	_loading = false

func _draft() -> Dictionary:
	var result := {"enabled":fields.enabled.button_pressed,"vision_input":fields.vision_input.button_pressed,"extra":fields.extra.text}
	for key: String in ["context_tokens","max_output_tokens","timeout_seconds","reasoning","verbosity","temperature","top_p"]: result[key] = fields[key].text
	for key: String in ["temperature_auto","top_p_auto"]: result[key] = fields[key].button_pressed
	for key: String in ["token_field","reasoning_field"]: result[key] = fields[key].selected
	return result

func _load_draft(draft: Dictionary) -> void:
	_loading = true
	for key: String in draft:
		if key in ["enabled","vision_input","temperature_auto","top_p_auto"]: fields[key].button_pressed = bool(draft[key])
		elif key in ["token_field","reasoning_field"]: fields[key].select(int(draft[key]))
		elif fields.has(key): fields[key].text = str(draft[key])
	for key: String in ["temperature","top_p"]: fields[key].editable = not fields[key+"_auto"].button_pressed
	_loading = false

func _changed() -> void:
	if _loading: return
	if drafts.size() >= 32 and not drafts.has(_key()): drafts.erase(drafts.keys()[0])
	drafts[_key()] = _draft()
	_validate()

func collect() -> Dictionary:
	var errors: Array = []
	var profile := {"enabled":fields.enabled.button_pressed,"vision_input":fields.vision_input.button_pressed}
	for key: String in ["context_tokens","max_output_tokens","timeout_seconds"]:
		var text: String = fields[key].text.strip_edges()
		if not text.is_valid_int(): errors.append(key+L.text(": введите целое число, 0 — автоматически."))
		else: profile[key] = int(text)
	for key: String in ["temperature","top_p"]:
		profile[key] = null
		if not fields[key+"_auto"].button_pressed:
			var text: String = fields[key].text.strip_edges().replace(",",".")
			if not text.is_valid_float(): errors.append(key+L.text(": введите число или включите автоматический режим."))
			else: profile[key] = float(text)
	for key: String in ["reasoning","verbosity"]: profile[key] = fields[key].text
	for key: String in ["token_field","reasoning_field"]: profile[key] = fields[key].get_selected_metadata()
	var json := JSON.new()
	if json.parse(fields.extra.text) != OK: errors.append("JSON: "+json.get_error_message()+L.text(" (строка ")+str(json.get_error_line())+").")
	elif not json.data is Dictionary: errors.append(L.text("JSON: нужен объект {…}, а не массив или отдельное значение."))
	else: profile.extra = json.data
	if not errors.is_empty(): return {"ok":false,"errors":errors,"profile":{}}
	return Policy.validate(profile)

func _validate() -> void:
	var checked: Dictionary = collect()
	_apply.disabled = not checked.ok or target_base == "" or target_model == ""
	var lines := PackedStringArray()
	for error: Variant in checked.get("errors",[]): lines.append(_translate_error(str(error)))
	_errors.text = "\n".join(lines)
	_errors.visible = not lines.is_empty()

func _translate_error(error: String) -> String:
	var translations := {
		"profile metadata is not an API generation parameter.":L.text("это настройка профиля, а не параметр генерации API."),
		"expected integer 0 (auto) through 10000000.":L.text("допустимо целое число от 0 (авто) до 10 000 000."),
		"expected integer 0 (auto) through 3600.":L.text("допустимо целое число от 0 (авто) до 3 600 секунд."),
		"expected null (auto) or number 0..2.":L.text("допустимо число 0–2 или автоматический режим."),
		"expected null (auto) or number 0..1.":L.text("допустимо число 0–1 или автоматический режим."),
		"expected an exact supported value up to 80 characters, or empty for auto.":L.text("нужно поддерживаемое значение до 80 символов; пусто — авто."),
		"routing, credentials, prompts, tools and streaming are protected.":L.text("адрес, авторизация, сообщения, инструменты и потоковый режим защищены."),
		"expected JSON object.":L.text("нужен JSON-объект."),
		"JSON exceeds depth 8 or 2048 values.":L.text("JSON превышает глубину 8 или 2 048 значений."),
		"JSON exceeds 65536 bytes.":L.text("JSON превышает 65 536 байт."),
		"JSON keys must be nonempty strings up to 160 characters.":L.text("ключи JSON должны содержать 1–160 символов."),
		"number must be finite.":L.text("нужно конечное число."),
		"only JSON data is allowed.":L.text("разрешены только данные JSON."),
		"expected native generation object.":L.text("нужен объект параметров генерации."),
		"conflicting generation token fields; choose one.":L.text("конфликт полей лимита ответа: оставьте одно."),
		"conflicting reasoning fields; choose one.":L.text("конфликт полей рассуждения: оставьте одно."),
		"conflicting verbosity fields; choose one.":L.text("конфликт полей подробности: оставьте одно."),
		"conflicting sampling fields; choose one protocol shape.":L.text("конфликт параметров сэмплирования: оставьте один формат API."),
		"output budget conflicts with max_output_tokens.":L.text("лимит ответа противоречит max_output_tokens."),
		"temperature must be 0..2.":L.text("температура должна быть от 0 до 2."),
		"top_p must be 0..1.":L.text("top_p должен быть от 0 до 1."),
		"choose a nonempty supported value.":L.text("нужно непустое поддерживаемое значение."),
		"output budget must be an integer from 1 to 10000000.":L.text("лимит ответа должен быть целым числом от 1 до 10 000 000.")
	}
	for phrase: String in translations: error = error.replace(phrase,translations[phrase])
	return error

func refresh() -> void:
	if fields.is_empty(): return
	var caps: Dictionary = owner_mod.capabilities_for(target_base,target_model) if target_base != "" else {}
	var lines := PackedStringArray()
	if caps.get("pending",false): lines.append(L.text("Получаем возможности модели…"))
	elif caps.get("error","") != "": lines.append(L.text("Возможности не получены. Ручные настройки доступны; совместимость проверит API."))
	elif not caps.has("supported_parameters"): lines.append(L.text("API не сообщил полный список параметров. Поддержка отдельных настроек неизвестна."))
	else: lines.append(L.text("API сообщил список параметров; допустимые значения зависят от модели."))
	if caps.get("context_tokens",0) > 0: lines.append(L.text("Контекст по данным API: ")+str(caps.context_tokens)+L.text(" токенов."))
	if caps.get("max_output_tokens",0) > 0: lines.append(L.text("Максимум ответа по данным API: ")+str(caps.max_output_tokens)+L.text(" токенов."))
	if caps.get("protocol","") != "": lines.append(L.text("Протокол: ")+str(caps.protocol))
	for key: String in ["reasoning","verbosity"]:
		var selector: OptionButton = fields[key+"_values"]; selector.clear()
		selector.add_item(L.text("Значения, объявленные API…")); selector.set_item_disabled(0,true)
		var values: Variant = caps.get(key+"_values",[])
		if values is Array:
			for value: Variant in values:
				if value is String and value != "": selector.add_item(value)
		selector.visible = selector.item_count > 1
		for i: int in range(1,selector.item_count):
			if selector.get_item_text(i) == fields[key].text: selector.select(i)
		if selector.visible: selector.tooltip_text = L.text("Значения, опубликованные API")
	if caps.get("supported_parameters") is Array and fields.enabled.button_pressed:
		for key: String in ["reasoning","verbosity","temperature","top_p"]:
			var selected: bool = fields[key].text != "" if key in ["reasoning","verbosity"] else not fields[key+"_auto"].button_pressed
			var parameters: Array = [key]
			if key == "reasoning":
				var selected_field: String = fields.reasoning_field.get_selected_metadata()
				parameters = ["reasoning_effort","reasoning"] if selected_field == "auto" else [selected_field.get_slice(".",0)]
			elif key == "verbosity": parameters = ["verbosity","text"]
			if selected and not parameters.any(func(parameter): return parameter in caps.supported_parameters): lines.append(L.text("API не объявил поддержку: ")+key+".")
	_caps.text = "\n".join(lines)
	_validate()

func _set_open(value: bool) -> void:
	_body.visible = value; _toggle.text = L.text("Тонкая настройка  ▾") if value else L.text("Тонкая настройка  ▸")
	if value: refresh(); capabilities_requested.emit(target_base,target_model)

func open() -> void: _set_open(true)

func _save() -> void:
	_changed()
	var checked: Dictionary = collect()
	if not checked.ok or _apply.disabled: return
	var result: Dictionary = owner_mod.save_profile(target_base,target_model,checked.profile)
	if not result.get("ok",false):
		_errors.text = L.text("Не удалось применить настройки.\n")+"\n".join(PackedStringArray(result.get("errors",[]))); _errors.show()
	else:
		drafts.erase(_key()); _load_profile(owner_mod.profile_for(target_base,target_model)); refresh()

func _reset() -> void:
	if target_base == "" or target_model == "": return
	var result: Dictionary = owner_mod.reset_profile(target_base,target_model)
	if result.get("ok",false): drafts.erase(_key()); _load_profile(owner_mod.profile_for(target_base,target_model)); refresh()
