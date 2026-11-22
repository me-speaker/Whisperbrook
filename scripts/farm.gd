extends RefCounted

const ITEMS = {
	"bean":{"name":"蚕豆","group":"vegetable","price":3},
	"turnip":{"name":"萝卜","group":"vegetable","price":2},
	"wood":{"name":"木料","group":"material","price":1}
}
const PEOPLE = {"carpenter":"陆木匠","shop":"阿禾","fisher":"周叔"}
const FIELDS = ["bean","turnip"]
const SLOT = "user://farm.json"
var s: Dictionary

func _init() -> void:
	s = {"version":1,"day":1,"minutes":420,"coins":6,"bag":{"bean":0,"turnip":0,"wood":0},
		"box":{"bean":0,"turnip":0,"wood":0},"pantry":{"bean":0,"turnip":0,"wood":0},
		"seeds":{"bean":3,"turnip":2},"crop":"bean","plots":[],"rules":{},"wood_day":0,
		"boat":0,"boat_agreed":false,"sold_veg":0,"ferry":false,"log":[],"talk":{}}
	for i in 6:
		s.plots.append({"item":"bean" if i < 3 else "", "age":2 if i < 3 else 0,"wet":false})

func weather(day: int) -> String:
	return "细雨" if day % 4 == 3 else "晴"

func log_line(line: String) -> void:
	s.log.append("第%d日　%s" % [s.day,line])
	if s.log.size() > 60: s.log.pop_front()

func later(n: int) -> void:
	s.minutes = mini(1199, s.minutes + n)

func work_plot(index: int) -> String:
	var p: Dictionary = s.plots[index]
	if p.item == "":
		var crop: String = s.crop
		if s.seeds[crop] < 1: return "种袋空了，可以去阿禾的铺子补些种子。"
		s.seeds[crop] -= 1
		p.merge({"item":crop,"age":0,"wet":weather(s.day)=="细雨"},true)
		later(12)
		return "种下了%s。" % ITEMS[crop].name
	if p.age >= 2:
		var name_: String = ITEMS[p.item].name
		s.bag[p.item] += 3
		p.merge({"item":"","age":0,"wet":false},true)
		later(9)
		return "收下 3 份%s。" % name_
	if p.wet or weather(s.day)=="细雨": return "土已经湿润，明早再来看。"
	p.wet = true
	later(8)
	return "浇透了，土色深了一层。"

func deposit() -> String:
	var total := 0
	for k in ITEMS:
		total += int(s.bag[k])
		s.box[k] += s.bag[k]
		s.bag[k] = 0
	return "放入 %d 份货物，今晚装船。" % total if total else "背篓空着。"

func gather() -> String:
	if s.wood_day == s.day: return "今日能拾的木料都收好了。"
	s.wood_day = s.day
	s.bag.wood += 2
	later(20)
	return "拾得 2 份木料。"

func buy_seed(item: String) -> String:
	if not item in FIELDS: return "没有这种种子。"
	if s.coins < 2: return "买一包种子需要 2 文。"
	s.coins -= 2
	s.seeds[item] += 3
	return "买下%s种子 3 粒。" % ITEMS[item].name

func label_for(selector: String) -> String:
	if selector == "vegetable": return "每种蔬菜"
	return ITEMS[selector].name if selector in ITEMS else selector

func describe(rule: Dictionary) -> String:
	var subject := label_for(rule.selector)
	match rule.action:
		"keep": return "%s各留 %d 份在家，其余出货" % [subject,rule.count] if rule.selector == "vegetable" else "%s留 %d 份在家，其余出货" % [subject,rule.count]
		"workshop": return "每晚拨最多 %d 份木料修船，修好即止" % rule.count
		"remove": return "撤回「%s」的单独约定" % subject
	return "%s照常全部出货" % subject

func validate(raw: Dictionary) -> Dictionary:
	var sel = raw.get("selector","")
	var act = raw.get("action","")
	if not sel is String or not act is String: return {"error":"没有认清对象和做法。"}
	if not (sel in ITEMS or sel=="vegetable") or not act in ["keep","sell","workshop","remove"]:
		return {"error":"这条约定暂时无法执行。"}
	if act=="workshop":
		if sel!="wood": return {"error":"工坊此刻只收修船的木料。"}
		if s.boat>=8: return {"error":"渡船已经修好，工坊收料已结束。"}
		if not s.boat_agreed: return {"error":"请先到河岸和陆木匠商量收料。"}
	if act=="remove" and not s.rules.has(sel): return {"error":"还没有这一项单独的约定。"}
	var amount = raw.get("count",0)
	if act in ["keep","workshop"]:
		if not (amount is int or amount is float): return {"error":"请写清要留几份。"}
		if amount!=int(amount) or amount<1 or amount>999: return {"error":"每次数量须为 1 至 999 份。"}
	else: amount=0
	return {"selector":sel,"action":act,"count":int(amount)}

func set_rule(raw: Dictionary) -> String:
	var r := validate(raw)
	if r.has("error"): return r.error
	if r.action=="remove": s.rules.erase(r.selector)
	else: s.rules[r.selector]=r
	log_line("托运簿改记："+describe(r))
	return "记好了，下次出货照此办理。"

func dispatch_plan() -> Dictionary:
	var result := {"coins":0,"kept":{},"sent":{},"sold":{}}
	for k in ITEMS:
		var qty: int = s.box[k]
		var rule: Dictionary = s.rules.get(k,s.rules.get(ITEMS[k].group,{}))
		var keep := 0
		var deliver := 0
		match rule.get("action","sell"):
			"keep": keep = mini(qty,rule.count)
			"workshop":
				if s.boat_agreed: deliver = mini(mini(qty,rule.count),8-s.boat)
		result.kept[k] = keep
		result.sent[k] = deliver
		result.sold[k] = qty-keep-deliver
		result.coins += (qty-keep-deliver)*int(ITEMS[k].price)
	return result

func night() -> String:
	var bill := dispatch_plan()
	for k in ITEMS:
		s.pantry[k] += bill.kept[k]
		s.box[k]=0
		if k in FIELDS: s.sold_veg += bill.sold[k]
	s.coins += bill.coins
	var old_boat: int = s.boat
	s.boat = mini(8,s.boat+int(bill.sent.wood)+(1 if weather(s.day)=="晴" else 0))
	if s.boat==8 and s.rules.get("wood",{}).get("action")=="workshop":
		s.rules.erase("wood")
		log_line("船板齐了，托运簿上的送木约定已结清。")
	var line := "出货 %d 文" % bill.coins
	for k in ITEMS:
		if bill.kept[k]: line += "，留%s %d 份" % [ITEMS[k].name,bill.kept[k]]
	if bill.sent.wood: line += "，送工坊 %d 份木料" % bill.sent.wood
	log_line(line)
	s.day += 1
	s.minutes = 420
	for p in s.plots:
		if p.item!="" and (p.wet or weather(s.day-1)=="细雨"): p.age=mini(2,p.age+1)
		p.wet=weather(s.day)=="细雨" and p.item!=""
	if old_boat<8 and s.boat==8: log_line("河岸的旧渡船修好了。")
	if s.boat==8 and s.day%2==0:
		s.ferry=true
		log_line("周叔系上铜铃，今晨开渡。")
	return line

func inventory(items: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in ITEMS:
		if items.get(k,0)>0: bits.append("%s %d" % [ITEMS[k].name,items[k]])
	return "空" if bits.is_empty() else "、".join(bits)

func save_to(path: String=SLOT) -> bool:
	var tmp := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if tmp==null: return false
	tmp.store_string(JSON.stringify(s))
	tmp.close()
	var fs := DirAccess.open("user://")
	if fs.file_exists(path):
		if fs.file_exists(path+".bak"): fs.remove(path+".bak")
		if fs.rename(path,path+".bak")!=OK: return false
	return fs.rename(path+".tmp",path)==OK

func restore(path: String=SLOT) -> bool:
	for candidate in [path,path+".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var data=JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if data is Dictionary and data.get("version")==1 and data.has_all(s.keys()) and data.plots is Array and data.plots.size()==6:
			s=data
			return true
	return false
