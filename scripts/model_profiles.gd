extends RefCounted

const DEFAULT = "riverbend_cloud_small"
const CATALOG_FILE = "res://config/model_presets.json"
var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_FILE))
var config := ConfigFile.new()
var path: String
var session_keys := {}
var env_endpoint := ""

func _init(file: String="user://model.cfg") -> void:
	path=file
	if FileAccess.file_exists(path): config.load(path)
	if config.has_section("model") and not config.has_section_key("roles","default"):
		var url:String=config.get_value("model","endpoint",catalog[DEFAULT].endpoint)
		var id:="openai_compatible"
		for candidate in catalog:
			if catalog[candidate].endpoint==url:
				id=candidate
				break
		var legacy:=preset(id)
		legacy.endpoint=url
		legacy.model=config.get_value("model","name",legacy.model)
		legacy.auth="bearer"
		legacy.output="json"
		config.set_value("roles","default",legacy)
	env_endpoint=config.get_value("environment","endpoint",profile("default").endpoint)

func preset(id:String) -> Dictionary:
	var entry:Dictionary=catalog[id]
	return {"id":id,"endpoint":entry.endpoint,"model":entry.model,"auth":entry.auth_type,"output":entry.output_mode}

func inherits(role:String) -> bool:
	return role!="default" and not config.has_section_key("roles",role)

func profile(role:String) -> Dictionary:
	return config.get_value("roles","default" if inherits(role) else role,preset(DEFAULT)).duplicate()

func validate(p:Dictionary) -> String:
	if not catalog.has(p.get("id","")): return "请选择接口预设。"
	var url:String=p.endpoint
	if not (url.begins_with("https://") or url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")) or "@" in url or " " in url:
		return "请填写完整的 HTTPS 或本机接口地址。"
	if str(p.model).strip_edges().is_empty(): return "请填写模型 ID。"
	if not p.auth in ["bearer","x-api-key","none"] or not p.output in ["tools","json"]: return "请重新选择认证与回复方式。"
	return ""

func remembered(url:String) -> bool:
	return config.has_section_key("keys",url.sha256_text())

# Only the current Windows user can unseal the stored blob. Arguments contain code only.
func crypt(value:String, seal:bool) -> String:
	if OS.get_name()!="Windows" or value.is_empty(): return ""
	var variable:="LIUCHA_DPAPI_VALUE"
	var command:="Add-Type -AssemblyName System.Security; $v=[Environment]::GetEnvironmentVariable('LIUCHA_DPAPI_VALUE'); "
	if seal:
		command+="[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($v),$null,'CurrentUser'))"
	else:
		command+="[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($v),$null,'CurrentUser'))"
	var result:=[]
	var executable:=OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	OS.set_environment(variable,value)
	var code:=OS.execute(executable,["-NoProfile","-NonInteractive","-Command",command],result)
	OS.unset_environment(variable)
	return str(result[0]).strip_edges() if code==OK and not result.is_empty() else ""

func explicit_key(url:String) -> String:
	if session_keys.has(url): return session_keys[url]
	if remembered(url):
		var key:=crypt(config.get_value("keys",url.sha256_text()),false)
		if not key.is_empty(): session_keys[url]=key
		return key
	return ""

func key_for(p:Dictionary) -> String:
	if p.auth=="none": return ""
	var key:=explicit_key(p.endpoint)
	if not key.is_empty(): return key
	if p.endpoint==env_endpoint:
		key=OS.get_environment("LIUCHA_API_KEY")
		if not key.is_empty(): return key
	for id in [DEFAULT,"riverbend_cloud_large"]:
		if p.endpoint==catalog[id].endpoint:
			var source:=OS.get_environment("LOCALAPPDATA").path_join("RiverBend/Cloud/api-key.txt")
			if FileAccess.file_exists(source): return FileAccess.get_file_as_string(source).strip_edges()
	return ""

func write_config() -> bool:
	if config.save(path+".tmp")!=OK: return false
	return DirAccess.rename_absolute(path+".tmp",path)==OK

func save(role:String,p:Dictionary,key:String,remember:bool) -> String:
	var error:=validate(p)
	if not error.is_empty(): return error
	var previous:=config.encode_to_text()
	var url:String=p.endpoint
	var value:=key if not key.is_empty() else explicit_key(url)
	var slot:=url.sha256_text()
	if remember and not value.is_empty():
		var encrypted:=crypt(value,true)
		if encrypted.is_empty(): return "系统未能加密密钥，设置未保存。"
		config.set_value("keys",slot,encrypted)
	elif remembered(url): config.erase_section_key("keys",slot)
	config.set_value("roles",role,p.duplicate())
	config.set_value("environment","endpoint",env_endpoint)
	if config.has_section("model"): config.erase_section("model")
	if not write_config():
		config.clear()
		config.parse(previous)
		return "配置文件写入失败。"
	if not value.is_empty(): session_keys[url]=value
	return ""

func inherit(role:String) -> bool:
	if role=="default" or inherits(role): return false
	var old:=profile(role)
	config.erase_section_key("roles",role)
	if write_config(): return true
	config.set_value("roles",role,old)
	return false

func forget(url:String) -> bool:
	if remembered(url):
		var slot:=url.sha256_text()
		var old:String=config.get_value("keys",slot)
		config.erase_section_key("keys",slot)
		if not write_config():
			config.set_value("keys",slot,old)
			return false
	session_keys.erase(url)
	return true
