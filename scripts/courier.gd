extends Node

const Profiles=preload("res://scripts/model_profiles.gd")
const Protocol=preload("res://scripts/model_protocol.gd")
var profiles=Profiles.new()
var busy:=false

func request(instruction:String, context:Dictionary, spoken:bool, role:String) -> Dictionary:
	var p:Dictionary=profiles.profile(role)
	return await send(p,profiles.key_for(p),instruction,context,spoken)

func probe(p:Dictionary, key:String, role:String) -> Dictionary:
	var error:String=profiles.validate(p)
	if error!="": return {"error":error}
	var resolved:=key if not key.is_empty() else str(profiles.key_for(p))
	if role in ["default","clerk"]:
		var result:=await send(p,resolved,"这是接口测试，只返回一个字段 question，内容为 OK。",{"request":"请提交测试结果"},false)
		if result.has("error"): return result
		if not result.has("question"): return {"error":"已收到回复，但拟约格式测试未通过。"}
		if role=="clerk": return result
	return await send(p,resolved,"这是接口测试，直接回复 OK。",{"player":"测试连接"},true)

func send(p:Dictionary,key:String,instruction:String,context:Dictionary,spoken:bool) -> Dictionary:
	if busy: return {"error":"还有一封回信在路上。"}
	busy=true
	var entry:Dictionary=profiles.catalog[p.id]
	var http:=HTTPRequest.new()
	http.max_redirects=0
	http.body_size_limit=2097152
	http.timeout=90
	add_child(http)
	var payload:=Protocol.payload(p,entry,instruction,context,spoken)
	var err:=http.request(p.endpoint,Protocol.headers(p,entry,key),HTTPClient.METHOD_POST,JSON.stringify(payload))
	if err!=OK:
		http.queue_free()
		busy=false
		return {"error":"连不上模型接口，可在设置里核对地址。"}
	var result=await http.request_completed
	http.queue_free()
	busy=false
	if result[0]!=HTTPRequest.RESULT_SUCCESS: return {"error":"未能连通接口。请检查地址、网络或本机云转发。"}
	if result[1]<200 or result[1]>=300: return {"error":"模型接口返回 HTTP %d，请核对密钥、模型 ID 和权限。" % result[1]}
	var json:=JSON.new()
	if json.parse(result[3].get_string_from_utf8())==OK and json.data is Dictionary:
		return Protocol.decode(entry,json.data,spoken)
	return {"error":"接口没有返回 JSON。"}

func clerk(farm, words: String) -> Dictionary:
	var prompt="你是柳汊镇的账房先生。根据玩家的完整意图拟一条长期托运规则。引擎只处理 nightly_shipping 时箱内的货。selector 从 items 的物品编号中选，或用 vegetable 表示每种蔬菜分别算。action=keep（每次留count份在家）/sell（全卖）/workshop（向已同意的木匠拨最多count份木料，直至船修好）/remove（撤回该对象规则）。具体物品规则优先于类别。count 为整数。完全能表达只回 {selector,action,count}。如条件、单位、动作不在能力中，或未能明确数量，回 {question:一句简短说明或澄清}；不得丢弃条件、代替居民同意或声称已生效。撤回后按余下规则执行。"
	prompt+=" 把口语中文数字转换为 JSON 整数。以最后的玩家原话为准，箱中现货与拟约数量无关；即使箱中没货也可先拟约。成功字段类型："+JSON.stringify({"selector":"string","action":"string","count":"integer"})+"。只有信息确实缺失才返回 question。"
	return await request(prompt,{"request":words,"rules":farm.s.rules,"workshop_accepts":farm.s.boat_agreed,"boat_progress":farm.s.boat,"box":farm.s.box,"items":farm.ITEMS},false,"clerk")

func speak(farm, person: String, words: String) -> Dictionary:
	var souls={"shop":"阿禾经营小铺，爽朗，关心供货是否稳定。","carpenter":"陆木匠，惜材，话少，宁肯慢慢修也要船能经风雨。你可自行决定是否愿收修船的木料。","fisher":"周叔，风趣，重视同女儿吃早饭，对天天开渡有保留。"}
	var prompt="你是江南水乡柳汊的居民。"+souls[person]+" 用一至两句有生活气息的中文直接回应玩家刚说的话。只根据可见事实，未发生的事不要说已经办成。只写原话，不加旁白或人物名。"
	if person=="carpenter": prompt+=" 仅当你与玩家确实达成收木料的约定时，在答话末尾另起一行写 @accept_wood。"
	return await request(prompt,{"day":farm.s.day,"season":farm.SEASONS[farm.season()],"weather":farm.weather(farm.s.day),"boat_out_of_8":farm.s.boat,"vegetables_delivered":farm.s.sold_veg,"ferry_open":farm.s.ferry,"wood_agreement":farm.s.boat_agreed,"friendship":farm.s.friendship.get(person,0),"received_gift_today":farm.s.gifts.get(person,0)==farm.s.day,"past":farm.s.talk.get(person,[]),"player":words},true,person)
