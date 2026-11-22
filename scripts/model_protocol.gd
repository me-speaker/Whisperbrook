extends RefCounted

const TOOL="draft_shipping_rule"
const SCHEMA={"type":"object","properties":{
	"selector":{"type":"string","enum":["vegetable","bean","turnip","wood"]},
	"action":{"type":"string","enum":["keep","sell","workshop","remove"]},
	"count":{"type":"integer"},"question":{"type":"string"}
},"additionalProperties":false}

static func headers(p:Dictionary, entry:Dictionary, key:String) -> PackedStringArray:
	var out:=PackedStringArray(["Content-Type: application/json"])
	if entry.protocol=="anthropic": out.append("anthropic-version: 2023-06-01")
	if not key.is_empty():
		if p.auth=="bearer": out.append("Authorization: Bearer "+key)
		if p.auth=="x-api-key": out.append("x-api-key: "+key)
	return out

static func payload(p:Dictionary, entry:Dictionary, system:String, context:Dictionary, spoken:bool) -> Dictionary:
	var facts:=context.duplicate()
	var words:String=facts.get("request",facts.get("player",""))
	facts.erase("request")
	facts.erase("player")
	var briefing:="只用于判断的游戏事实："+JSON.stringify(facts)
	var listed:bool=p.endpoint==entry.endpoint and p.model in entry.models
	var tools:bool=not spoken and p.output=="tools" and not (listed and p.model in entry.get("json_only_models",[]))
	var user:={"role":"user","content":words}
	var body:={"model":p.model}
	body[entry.token_parameter]=1536
	if not spoken:
		system+=" 返回合法 JSON，对象键名和字符串值都用英文双引号。" if not tools else " 使用拟约工具提交约定或澄清问题。"
	if entry.protocol=="anthropic":
		body.system=system+"\n"+briefing
		body.messages=[user]
		if tools:
			body.tools=[{"name":TOOL,"description":"提交拟定的托运规则，或填写需要澄清的问题。","input_schema":SCHEMA}]
			body.tool_choice={"type":"auto"}
	else:
		var role:String=entry.get("system_role","system")
		body.messages=[{"role":role,"content":system},{"role":role,"content":briefing},user]
		if listed: body.merge(entry.get("request_options",{}),true)
		if p.id in ["riverbend_cloud_small","riverbend_cloud_large"]: body.temperature=0.15
		if listed and p.id=="minimax_browser":
			if p.model=="MiniMax-M3.1-Flash": body.reasoning_effort="low"
			elif p.model=="MiniMax-M3":
				body.thinking={"type":"disabled"}
				body.reasoning_split=true
		if tools:
			body.tools=[{"type":"function","function":{"name":TOOL,"description":"提交拟约或澄清问题。","parameters":SCHEMA}}]
			body.tool_choice="auto"
	return body

static func decode(entry:Dictionary, data:Dictionary, spoken:bool) -> Dictionary:
	var content
	if entry.protocol=="anthropic":
		if data.get("stop_reason")=="max_tokens": return {"error":"模型回复达到输出上限。"}
		content=data.get("content",[])
	else:
		var choices=data.get("choices",[])
		if not choices is Array or choices.is_empty() or not choices[0] is Dictionary: return {"error":"模型接口未返回答复。"}
		if choices[0].get("finish_reason")=="length": return {"error":"模型回复达到输出上限。"}
		var m=choices[0].get("message",{})
		if not m is Dictionary: return {"error":"模型接口未返回消息。"}
		content=m.get("content","")
		if not spoken and m.get("tool_calls") is Array:
			for call in m.tool_calls:
				if not call is Dictionary: continue
				var fn=call.get("function",{})
				if fn is Dictionary and fn.get("name")==TOOL:
					content=fn.get("arguments","")
					break
	if content is Array:
		var text:=""
		for part in content:
			if not part is Dictionary: continue
			if not spoken and part.get("type")=="tool_use" and part.get("name")==TOOL and part.get("input") is Dictionary:
				return part.input
			if part.get("type")=="text" and part.get("text") is String: text+=part.text
		content=text
	if content is String:
		var text:String=content.strip_edges()
		while "<think>" in text:
			var start:=text.find("<think>")
			var end:=text.find("</think>",start)
			text=text.left(start)+(text.substr(end+8) if end>=0 else "")
		text=text.strip_edges()
		if spoken and not text.is_empty():
			var agreed:=text.ends_with("@accept_wood")
			text=text.trim_suffix("@accept_wood").strip_edges()
			if not text.is_empty(): return {"line":text,"accept_wood":agreed}
		elif not spoken:
			var start:=text.find("{")
			var end:=text.rfind("}")
			var parsed:=JSON.new()
			if start>=0 and end>=start and parsed.parse(text.substr(start,end-start+1))==OK and parsed.data is Dictionary:
				return parsed.data
	return {"error":"模型回复格式未能识别，可在设置中切换账房回复方式。"}
