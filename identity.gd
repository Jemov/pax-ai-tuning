extends RefCounted
## Profile identities are public endpoint/model values, never credentials.
static func base_url(value: String) -> String:
	var base: String = value.strip_edges()
	while base.ends_with("/"): base = base.trim_suffix("/")
	if "?" in base or "#" in base or "\\" in base: return ""
	var matched: RegExMatch = RegEx.create_from_string("^(https?)://(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9][A-Za-z0-9.-]*)(:[0-9]{1,5})?(/[^\\s@?#]*)?$").search(base)
	if matched == null: return ""
	var host: String = matched.get_string(2).to_lower()
	if matched.get_string(1) == "http" and host not in ["localhost","127.0.0.1","[::1]"]: return ""
	var port: String = matched.get_string(3)
	if port != "" and (port.substr(1).to_int() < 1 or port.substr(1).to_int() > 65535): return ""
	return matched.get_string(1)+"://"+host+port+matched.get_string(4).trim_suffix("/")

static func key(base: String, model: String) -> String:
	var normalized: String = base_url(base)
	var selected: String = model.strip_edges()
	if normalized == "" or selected == "" or selected.length() > 512: return ""
	return JSON.stringify([normalized,selected]).sha256_text()
