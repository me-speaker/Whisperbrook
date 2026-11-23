extends RefCounted

const ITEMS = {
	"bean":{"name":"蚕豆","group":"vegetable","price":3},
	"turnip":{"name":"萝卜","group":"vegetable","price":2},
	"wood":{"name":"木料","group":"material","price":1},
	"lotus":{"name":"菱角","group":"vegetable","price":4},
	"taro":{"name":"芋头","group":"vegetable","price":5},
	"fish":{"name":"河鲫","group":"catch","price":6},
	"herb":{"name":"马兰头","group":"forage","price":2}
}
const PEOPLE = {"carpenter":"陆木匠","shop":"阿禾","fisher":"周叔"}
const FIELDS = ["bean","turnip","lotus","taro"]
const CROPS = {"bean":[0,2],"turnip":[0,1,2,3],"lotus":[1],"taro":[2]}
const SEASONS = ["春","夏","秋","冬"]
const GROWTH = {"bean":2,"turnip":2,"lotus":3,"taro":4}
const MAX_ENERGY = 40
const CAN_SIZE = 6
const TIRED = "有些乏了。吃些东西，或回家早些歇息。"
const SLOT = "user://farm.json"
const YARD_ORIGIN = Vector2(16,266)
const TILE = Vector2(70,40)
const YARD_COLS = 13
const YARD_ROWS = 4
const BRUSH = [7,9,11,21,23,33,35,37]
const LEGACY_START = [1,2,3,7,8,9]
const LEGACY_SITES = [0,1,2,3,4,5,6,7,8,9,10,11,13,14,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32]
const BUILD = {
	"field":{"name":"菜畦","wood":0,"minutes":20},
	"chest":{"name":"田头出货箱","wood":2,"minutes":30}
}
var s: Dictionary

func upgrade_household(data:Dictionary) -> void:
	for container in ["bag","box","pantry"]:
		for item in ITEMS:
			if not data[container].has(item): data[container][item]=0
	for crop in FIELDS:
		if not data.seeds.has(crop): data.seeds[crop]=0
	data.merge({"energy":MAX_ENERGY,"water":CAN_SIZE,"can_level":0,"foraged":[],"gifts":{},"friendship":{},"zone":"farm","location":[],"tool":"hand","cleared":[],"delivery_day":0},false)
	for i in data.cleared.size(): data.cleared[i]=int(data.cleared[i])
	if not data.has("last_shipment"): data.last_shipment={}

func capacity() -> int:
	return CAN_SIZE+6*int(s.can_level)

func improve_can() -> String:
	if s.can_level>0: return "已经装好大水胆了。"
	if s.coins<18 or s.bag.wood<2: return "换水胆需要 18 文和背篓里的两份木料。"
	s.coins-=18
	s.bag.wood-=2
	s.can_level=1
	log_line("陆木匠装上大水胆，一壶可浇十二畦。")
	return "新水胆已装好，可到井边汲满十二份水。"

func cook() -> String:
	if s.energy>=MAX_ENERGY: return "今天精神正好，鱼汤留到劳作后再煮。"
	for k in ["fish","herb"]:
		if s.bag[k]+s.pantry[k]<1: return "一碗马兰鲫鱼汤，需要一尾河鲫和一把马兰头。"
	for k in ["fish","herb"]:
		var supply:Dictionary=s.pantry if s.pantry[k]>0 else s.bag
		supply[k]-=1
	later(15)
	s.energy=mini(MAX_ENERGY,int(s.energy)+22)
	log_line("用家里的鱼和野菜煮了一碗汤。")
	return "喝过马兰鲫鱼汤，恢复了体力。"

func has_brush(site:int) -> bool:
	return site in BRUSH and site not in s.cleared

func clear_brush(site:int) -> String:
	if not has_brush(site): return "这里已清理。"
	if s.energy<2: return TIRED
	spend(2,10)
	s.cleared.append(site)
	s.bag.wood+=1
	return "理净枯枝，收得一份木料。现在可以开畦了。"

func _init() -> void:
	s = {"version":3,"legacy_box":false,"day":1,"minutes":420,"coins":6,"bag":{"bean":0,"turnip":0,"wood":2},
		"box":{"bean":0,"turnip":0,"wood":0},"pantry":{"bean":0,"turnip":0,"wood":0},
		"seeds":{"bean":3,"turnip":2},"crop":"bean","plots":[],"rules":{},"wood_day":0,
		"boat":0,"boat_agreed":false,"sold_veg":0,"ferry":false,"log":[],"talk":{},"chests":[]}
	upgrade_household(s)

func season() -> int:
	return floori((int(s.day)-1)/14.0)%4

func season_day() -> int:
	return (int(s.day)-1)%14+1

func spend(energy:int,minutes:int) -> void:
	s.energy-=energy
	later(minutes)

func forage(site:String) -> String:
	if site in s.foraged: return "这丛已经采过，明天再来。"
	if s.energy<2: return TIRED
	spend(2,8)
	s.foraged.append(site)
	s.bag.herb+=2
	return "掐了两把马兰头，可以吃，也可以装箱。"

func cast_line() -> String:
	if s.energy<3: return TIRED
	spend(3,12)
	return ""

func eat(item:String) -> String:
	if item=="fish": return "鲜鱼可以带回家下锅。"
	if item not in ["bean","turnip","lotus","taro","herb"] or s.bag[item]<=0: return "背篓中没有这份食材。"
	if s.energy>=MAX_ENERGY: return "已经精神饱满了。"
	s.bag[item]-=1
	s.energy=mini(MAX_ENERGY,int(s.energy)+5)
	return "歇了一会儿，精神好多了。"

func give(person:String,item:String) -> String:
	if person not in PEOPLE or item not in ITEMS or s.bag[item]<1: return "背篓里没有这份礼。"
	if s.gifts.get(person,0)==s.day: return "今天已经送过礼了。"
	s.bag[item]-=1
	s.gifts[person]=s.day
	var favourite:Dictionary={"shop":"bean","fisher":"herb","carpenter":"wood"}
	var change:=2 if favourite[person]==item else 1
	s.friendship[person]=s.friendship.get(person,0)+change
	var msg:="%s收下了%s%s" % [PEOPLE[person],ITEMS[item].name,"，看得出很喜欢。" if change==2 else "。"]
	log_line(msg)
	return msg

func free_site(site:int) -> bool:
	if site<0 or site>=YARD_COLS*YARD_ROWS or site in s.chests: return false
	for plot in s.plots:
		if plot.site==site: return false
	return true

func tile_center(site:int) -> Vector2:
	return YARD_ORIGIN+(Vector2(site%YARD_COLS,floori(float(site)/YARD_COLS))+Vector2(0.5,0.5))*TILE

func tile_at(p:Vector2) -> int:
	var cell:=Vector2i(((p-YARD_ORIGIN)/TILE).floor())
	if not Rect2i(0,0,YARD_COLS,YARD_ROWS).has_point(cell): return -1
	return cell.y*YARD_COLS+cell.x

func reclaim(site:int) -> String:
	if site==-1 and s.legacy_box:
		s.legacy_box=false
	elif site in s.chests:
		s.chests.erase(site)
	else:
		for i in s.plots.size():
			if s.plots[i].site!=site: continue
			if s.plots[i].item!="": return "这一畦还有作物，收获后可以平整。"
			s.plots.remove_at(i)
			return "菜畦已平整，可以重新布局。"
		return "这里已经是草地。"
	s.bag.wood+=BUILD.chest.wood
	return "已收回箱板，可到别处重搭。晚船货单仍然有效。"

func build(kind:String,site:int) -> String:
	if not BUILD.has(kind) or not free_site(site): return "请在院内挑一块空草地。"
	if has_brush(site): return "这里有枯枝，先用短锄清理。"
	var cost:Dictionary=BUILD[kind]
	if s.bag.wood<cost.wood: return "需要背篓里的 %d 份木料，可到木工棚前拾取。" % cost.wood
	if s.minutes+cost.minutes>1199: return "天色晚了，明早再来动工吧。"
	if s.energy<3: return TIRED
	s.bag.wood-=cost.wood
	spend(3,cost.minutes)
	if kind=="field": s.plots.append({"site":site,"item":"","age":0,"wet":weather(s.day)=="细雨"})
	else: s.chests.append(site)
	var message:="新菜畦已开好，可以播种了。" if kind=="field" else "田头出货箱已搭好，货物随晚船一起结算。"
	log_line(message)
	return message

func weather(day: int) -> String:
	return "细雨" if day % 4 == 3 else "晴"

func log_line(line: String) -> void:
	s.log.append("第%d日　%s" % [s.day,line])
	if s.log.size() > 60: s.log.pop_front()

func later(n: int) -> void:
	s.minutes = mini(1320, s.minutes + n)

func work_plot(index: int) -> String:
	var p: Dictionary = s.plots[index]
	if s.tool=="seed":
		var crop: String = s.crop
		if p.item!="": return "这里已经种着"+ITEMS[p.item].name+"。"
		if season() not in CROPS[crop]: return "这袋种子不适合本季播种。"
		if s.seeds[crop] < 1: return "种袋空了，可以去阿禾的铺子补些种子。"
		if s.energy<1: return TIRED
		s.seeds[crop] -= 1
		p.merge({"item":crop,"age":0,"wet":p.wet or weather(s.day)=="细雨"},true)
		spend(1,8)
		return "种下了%s。" % ITEMS[crop].name
	if s.tool=="can":
		if p.wet or weather(s.day)=="细雨": return "土已经湿润了。"
		if s.water<=0: return "水壶空了，去院里的井边汲水。"
		if s.energy<1: return TIRED
		s.water-=1
		p.wet=true
		spend(1,5)
		return "浇透了，土色深了一层。"
	if s.tool=="hand" and p.item!="" and p.age>=GROWTH[p.item]:
		var name_: String = ITEMS[p.item].name
		s.bag[p.item] += 3
		p.merge({"item":"","age":0,"wet":false},true)
		later(9)
		return "收下 3 份%s。" % name_
	if p.item=="": return "选种袋播种，或先用水壶润土。"
	return "已成熟，换空手采收。" if p.age>=GROWTH[p.item] else "还在生长，干土需要浇水。"

func deposit() -> String:
	var total := 0
	for k in ITEMS:
		total += int(s.bag[k])
		s.box[k] += s.bag[k]
		s.bag[k] = 0
	return "放入 %d 份货物，今晚装船。" % total if total else "背篓空着。"

func gather() -> String:
	if s.wood_day == s.day: return "今日能拾的木料都收好了。"
	if s.energy<2: return TIRED
	s.wood_day = s.day
	s.bag.wood += 2
	spend(2,15)
	return "拾得 2 份木料。"

func buy_seed(item: String) -> String:
	if s.minutes>=1080: return "菜铺已经收摊，明早七点再来。"
	if not item in FIELDS: return "没有这种种子。"
	if season() not in CROPS[item]: return "小铺本季没有这包种子。"
	if s.coins < 2: return "买一包种子需要 2 文。"
	s.coins -= 2
	var quantity:=4 if s.friendship.get("shop",0)>=4 else 3
	s.seeds[item] += quantity
	return "买下%s种子 %d 粒。" % [ITEMS[item].name,quantity]

func early_market() -> bool:
	return s.ferry and int(s.day)%2==0 and s.minutes<720

func trade_fish() -> String:
	if not early_market(): return "早渡鱼市已经散了。"
	var n:int=s.bag.fish
	if n==0: return "背篓里没有鲜鱼。"
	s.bag.fish=0
	s.coins+=8*n
	var msg:="阿禾收下 %d 尾河鲫，现付 %d 文。" % [n,8*n]
	log_line(msg)
	return msg

func market_request() -> Dictionary:
	match (int(s.day)-1)%3:
		0: return {"person":"shop","item":["bean","lotus","taro","turnip"][season()],"quantity":3,"use":"给街坊凑一篮时蔬"}
		1: return {"person":"fisher","item":"herb","quantity":2,"use":"带回家包一笼青团"}
	return {"person":"carpenter","item":"fish","quantity":1,"use":"给收工的帮手做晚饭"}

func deliver_request() -> String:
	if s.delivery_day==s.day: return "这张托单今天已经结清。"
	var job:=market_request()
	if s.bag[job.item]<job.quantity: return "背篓里的货还没凑齐。"
	var pay:int=job.quantity*(ITEMS[job.item].price+1)+2
	s.bag[job.item]-=job.quantity
	s.coins+=pay
	s.delivery_day=s.day
	s.friendship[job.person]=s.friendship.get(job.person,0)+1
	var receipt:="替%s送齐%s，收到 %d 文。" % [PEOPLE[job.person],ITEMS[job.item].name,pay]
	log_line(receipt)
	return receipt

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
	s.last_shipment=bill.duplicate(true)
	s.last_shipment.day=s.day
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
	s.energy=MAX_ENERGY
	s.foraged.clear()
	for p in s.plots:
		if p.item!="" and (p.wet or weather(s.day-1)=="细雨"): p.age=mini(GROWTH[p.item],p.age+1)
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
		if not data is Dictionary or not data.get("plots") is Array: continue
		if data.get("version")==1 and data.plots.size()==LEGACY_START.size():
			for i in LEGACY_START.size():
				if data.plots[i] is Dictionary: data.plots[i]["site"]=LEGACY_START[i]
			data.chests=[]
			data.version=2
		if data.get("version")==2:
			if not migrate_yard(data): continue
		if data.get("version")==3 and data.has_all(["bag","box","pantry","seeds"]): upgrade_household(data)
		if data.get("version")==3 and data.has_all(s.keys()) and valid_yard(data):
			data.day=int(data.day)
			s=data
			return true
	return false

func migrate_yard(data:Dictionary) -> bool:
	if not data.get("chests") is Array: return false
	for p in data.plots:
		if not p is Dictionary or legacy_site(p.get("site",-1))<0: return false
		p.site=legacy_site(p.site)
	for key in ["chests","cleared"]:
		if not data.has(key): continue
		for i in data[key].size():
			var site:=legacy_site(data[key][i])
			if site<0: return false
			data[key][i]=site
	data.legacy_box=true
	data.version=3
	return true

func legacy_site(value:Variant) -> int:
	if not (value is float or value is int) or int(value)!=value or int(value) not in LEGACY_SITES: return -1
	var site:=int(value)
	if site>=18: return 7+(site-18)%5+floori(float(site-18)/5)*YARD_COLS
	return 1+site%6+floori(float(site)/6)*YARD_COLS

func valid_yard(data:Dictionary) -> bool:
	if not data.chests is Array: return false
	var sites:Array=data.chests.duplicate()
	for plot in data.plots:
		if not plot is Dictionary or not plot.has_all(["site","item","age","wet"]): return false
		sites.append(plot.site)
	var seen:={}
	for site in sites:
		if not (site is int or site is float) or site!=int(site) or site<0 or site>=YARD_ROWS*YARD_COLS or seen.has(int(site)): return false
		seen[int(site)]=true
	for i in data.chests.size(): data.chests[i]=int(data.chests[i])
	for plot in data.plots: plot.site=int(plot.site)
	return true
