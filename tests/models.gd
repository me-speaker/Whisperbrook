extends SceneTree

const Town=preload("res://scripts/town.gd")
const Profiles=preload("res://scripts/model_profiles.gd")
const Protocol=preload("res://scripts/model_protocol.gd")
var failures:=0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	if ok: print("PASS ",label)
	else:
		failures+=1
		printerr("FAIL ",label)

func run() -> void:
	game=Town.new()
	var tmp:="user://qa-models-"+str(Time.get_ticks_usec())
	game.save_path=tmp+".farm"
	root.add_child(game)
	var cfg:=ConfigFile.new()
	cfg.set_value("model","endpoint","https://legacy.example/v1/chat/completions")
	cfg.set_value("model","name","local-model")
	cfg.save(tmp)
	var profiles=Profiles.new(tmp)
	game.ai.profiles=profiles
	check(profiles.profile("shop").model=="local-model" and profiles.inherits("shop"),"old global settings inherited")
	var first:Dictionary=profiles.preset(Profiles.DEFAULT)
	check(profiles.save("default",first,"",false)=="","save global Qwen")
	game.settings_page()
	game.edit_model("clerk")
	var picker:OptionButton=game.content.find_children("*","OptionButton",false,false)[0]
	var providers:Array=profiles.catalog.keys()
	check(picker.item_count==providers.size(),"settings list every catalog entry")
	var idx:=providers.find("riverbend_cloud_large")
	picker.select(idx)
	picker.item_selected.emit(idx)
	for button in game.content.find_children("*","Button",true,false):
		if button.text=="保存并使用":
			button.pressed.emit()
			break
	check(profiles.profile("clerk").id=="riverbend_cloud_large" and profiles.profile("fisher").id==Profiles.DEFAULT,"UI saves only selected role")
	if "--live" in OS.get_cmdline_user_args():
		var response:Dictionary=await game.ai.clerk(game.farm,"每晚给我留三份蚕豆，其余出货")
		check(response.get("selector")=="bean" and response.get("count")==3,"live 14B ledger request")
		var probe:Dictionary=await game.ai.probe(first,"","default")
		check(not probe.has("error"),"7B settings test covers structured and spoken replies")
	var p:Dictionary=profiles.preset("anthropic")
	var entry:Dictionary=profiles.catalog[p.id]
	var hello={"request":"问候"}
	var body:=Protocol.payload(p,entry,"规则",hello,false)
	check(body.has("system") and body.messages.size()==1 and body.tools[0].has("input_schema"),"Anthropic Messages and tools")
	var h:=Protocol.headers(p,entry,"sample")
	check("x-api-key: sample" in h and "anthropic-version: 2023-06-01" in h,"native Anthropic authentication")
	var payload={"question":"请问多少？"}
	var reply:=Protocol.decode(entry,{"content":[{"type":"thinking","thinking":"private"},{"type":"tool_use","name":Protocol.TOOL,"input":payload}]},false)
	check(reply==payload,"Anthropic tool result")
	reply=Protocol.decode(entry,{"content":[{"type":"thinking","thinking":"private"},{"type":"text","text":"你好"}]},true)
	check(reply.line=="你好","Anthropic NPC text blocks")
	p=profiles.preset("minimax_browser")
	entry=profiles.catalog[p.id]
	body=Protocol.payload(p,entry,"规则",hello,false)
	check(body.tools[0].function.name==Protocol.TOOL,"OpenAI-compatible tool schema")
	reply=Protocol.decode(entry,{"choices":[{"message":{"content":null,"tool_calls":[{"function":{"name":Protocol.TOOL,"arguments":JSON.stringify(payload)}}]}}]},false)
	check(reply==payload,"OpenAI-compatible tool result")
	if OS.get_name()=="Windows":
		var secret:="qa-"+str(Time.get_ticks_usec())
		check(profiles.save("shop",p,secret,true)=="","encrypt in current Windows account")
		check(secret not in FileAccess.get_file_as_string(tmp),"no plaintext in local settings")
		var restored=Profiles.new(tmp)
		check(restored.key_for(p)==secret and restored.profile("clerk").id=="riverbend_cloud_large","restart restores protected key and role")
		var changed:Dictionary=p.duplicate()
		changed.endpoint="https://other.example/v1/chat/completions"
		check(restored.key_for(changed)=="","key isolated by endpoint")
		check(restored.forget(p.endpoint) and restored.explicit_key(p.endpoint)=="","clear saved key")
	check(profiles.inherit("clerk") and profiles.profile("clerk").id==Profiles.DEFAULT,"resume global settings")
	for suffix in ["",".tmp"]:
		if FileAccess.file_exists(tmp+suffix): DirAccess.remove_absolute(tmp+suffix)
	quit(1 if failures else 0)
