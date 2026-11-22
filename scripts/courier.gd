extends Node

const LOCAL_URL = "http://127.0.0.1:18760/v1/chat/completions"
var endpoint := LOCAL_URL
var model := "Qwen/Qwen2.5-7B-Instruct"
var token := ""
var busy := false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://model.cfg")==OK:
		endpoint=cfg.get_value("model","endpoint",LOCAL_URL)
		model=cfg.get_value("model","name",model)
	token=OS.get_environment("LIUCHA_API_KEY")

func settings(url: String, name_: String, key: String) -> String:
	if not (url.begins_with("https://") or url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")) or name_.is_empty():
		return "请填写 HTTPS 或本机接口及模型 ID。"
	endpoint=url
	model=name_
	token=key
	var cfg:=ConfigFile.new()
	cfg.set_value("model","endpoint",endpoint)
	cfg.set_value("model","name",model)
	cfg.save("user://model.cfg")
	return "接口已记下。"

func request(instruction: String, context: Dictionary, spoken:=false) -> Dictionary:
	if busy: return {"error":"还有一封回信在路上。"}
	busy=true
	var http:=HTTPRequest.new()
	add_child(http)
	http.timeout=32
	var key:=token
	if key.is_empty() and endpoint==LOCAL_URL:
		var file:=OS.get_environment("LOCALAPPDATA").path_join("RiverBend/Cloud/api-key.txt")
		if FileAccess.file_exists(file): key=FileAccess.get_file_as_string(file).strip_edges()
	var headers:=PackedStringArray(["Content-Type: application/json"])
	if not key.is_empty(): headers.append("Authorization: Bearer "+key)
	var turns:Array=[{"role":"system","content":instruction if spoken else instruction+" 返回合法 JSON，对象键名和字符串值都用英文双引号。"}]
	var facts:Dictionary=context.duplicate()
	var utterance:String=facts.get("request",facts.get("player",""))
	facts.erase("request")
	facts.erase("player")
	turns.append({"role":"system","content":"只用于判断的游戏事实："+JSON.stringify(facts)})
	turns.append({"role":"user","content":utterance})
	var payload={"model":model,"temperature":0.15,"max_tokens":512,"messages":turns}
	var err:=http.request(endpoint,headers,HTTPClient.METHOD_POST,JSON.stringify(payload))
	if err!=OK:
		busy=false
		http.queue_free()
		return {"error":"连不上模型接口，可在设置里核对地址。"}
	var result=await http.request_completed
	http.queue_free()
	busy=false
	if result[0]!=HTTPRequest.RESULT_SUCCESS or result[1]<200 or result[1]>=300:
		return {"error":"模型暂未回信（HTTP %d），可再试或检查接口。" % result[1]}
	var data=JSON.parse_string(result[3].get_string_from_utf8())
	if data is Dictionary and data.get("choices") is Array and not data.choices.is_empty():
		var message=data.choices[0].get("message",{}).get("content","")
		if message is String:
			if spoken:
				var reply:String=message.strip_edges()
				var agreed:=reply.ends_with("@accept_wood")
				reply=reply.trim_suffix("@accept_wood").strip_edges()
				if not reply.is_empty(): return {"line":reply,"accept_wood":agreed}
			var a: int=message.find("{")
			var b: int=message.rfind("}")
			if a>=0 and b>=a:
				var parsed:=JSON.new()
				if parsed.parse(message.substr(a,b-a+1))==OK and parsed.data is Dictionary: return parsed.data
	return {"error":"回信格式没有读清，请再试一次。"}

func clerk(farm, words: String) -> Dictionary:
	var prompt="你是柳汊镇的账房先生。根据玩家的完整意图拟一条长期托运规则。引擎只处理 nightly_shipping 时箱内的货。selector=bean/turnip/wood/vegetable（各类蔬菜分别算），action=keep（每次留count份在家）/sell（全卖）/workshop（向已同意的木匠拨最多count份木料，直至船修好）/remove（撤回该对象规则）。具体物品规则优先于类别。count 为整数。完全能表达只回 {selector,action,count}。如条件、单位、动作不在能力中，或未能明确数量，回 {question:一句简短说明或澄清}；不得丢弃条件、代替居民同意或声称已生效。撤回后按余下规则执行。"
	prompt+=" 把口语中文数字转换为 JSON 整数。以最后的玩家原话为准，箱中现货与拟约数量无关；即使箱中没货也可先拟约。成功字段类型："+JSON.stringify({"selector":"string","action":"string","count":"integer"})+"。只有信息确实缺失才返回 question。"
	return await request(prompt,{"request":words,"rules":farm.s.rules,"workshop_accepts":farm.s.boat_agreed,"boat_progress":farm.s.boat,"box":farm.s.box,"items":farm.ITEMS})

func speak(farm, person: String, words: String) -> Dictionary:
	var souls={"shop":"阿禾经营小铺，爽朗，关心供货是否稳定。","carpenter":"陆木匠，惜材，话少，宁肯慢慢修也要船能经风雨。你可自行决定是否愿收修船的木料。","fisher":"周叔，风趣，重视同女儿吃早饭，对天天开渡有保留。"}
	var prompt="你是江南水乡柳汊的居民。"+souls[person]+" 用一至两句有生活气息的中文直接回应玩家刚说的话。只根据可见事实，未发生的事不要说已经办成。只写原话，不加旁白或人物名。"
	if person=="carpenter": prompt+=" 仅当你与玩家确实达成收木料的约定时，在答话末尾另起一行写 @accept_wood。"
	return await request(prompt,{"day":farm.s.day,"weather":farm.weather(farm.s.day),"boat_out_of_8":farm.s.boat,"vegetables_delivered":farm.s.sold_veg,"ferry_open":farm.s.ferry,"wood_agreement":farm.s.boat_agreed,"past":farm.s.talk.get(person,[]),"player":words},true)
