extends Node2D

const Farm = preload("res://scripts/farm.gd")
const Map = preload("res://scripts/riverbank.gd")
const Courier = preload("res://scripts/courier.gd")
const Sounds = preload("res://scripts/sounds.gd")
const INK:=Color("#274136")
const CREAM:=Color("#f5ecd5")
const KIT={"hand":"空手","hoe":"短锄","seed":"种袋","can":"水壶","rod":"竹竿"}
var kit_buttons:Dictionary={}
var energy_bar:ProgressBar
var fishing_time:=0.0
var bite_at:=0.0
var farm=Farm.new()
var map=Map.new()
var ai=Courier.new()
var sfx=Sounds.new()
var hud:=Control.new()
var title_font:=SystemFont.new()
var ui_font:=SystemFont.new()
var clock_label:Label
var wallet:Label
var pack:Label
var hint:Label
var toast:Label
var marker:Label
var build_button:Button
var popup:ColorRect
var content:VBoxContainer
var sheet_title:Label
var scroll:ScrollContainer
var preview: Dictionary={}
var page:=""
var epoch:=0
var notice_time:=0.0
var npc:=""
var last_day:=0
var clerk_thread:Array=[]
var loaded:=false
var save_path:String=Farm.SLOT

func _ready() -> void:
	loaded=farm.restore(save_path)
	title_font.font_names=PackedStringArray(["STZhongsong","SimSun","Noto Serif CJK SC"])
	ui_font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"])
	# Canvas-items stretch renders at window resolution in the original 960×540 world coordinates.
	map.farm=farm
	add_child(map)
	map.font=ui_font
	map.arrived.connect(interact)
	map.day_ended.connect(sleep_night)
	add_child(ai)
	add_child(sfx)
	var layer:=CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_override("font",ui_font)
	make_hud()
	update_hud()
	if not loaded: notify("短锄按 2，选一格草地开畦。背篓里有种子和两份搭箱的木料。",12)

func plate(bg: Color, border: Color, radius:=5, pad:=8) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=bg
	box.border_color=border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left=pad
	box.content_margin_right=pad
	box.content_margin_top=5
	box.content_margin_bottom=5
	return box

func lab(text_: String, px:=16, color:=INK, heading:=false) -> Label:
	var l:=Label.new()
	l.text=text_
	l.add_theme_font_override("font",title_font if heading else ui_font)
	l.add_theme_font_size_override("font_size",px)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return l

func btn(caption: String, fn: Callable, primary:=false) -> Button:
	var b:=Button.new()
	b.text=caption
	b.add_theme_font_override("font",ui_font)
	b.add_theme_font_size_override("font_size",14)
	b.add_theme_color_override("font_color",CREAM if primary else INK)
	b.add_theme_color_override("font_hover_color",Color.WHITE)
	b.add_theme_color_override("font_pressed_color",Color.WHITE)
	b.add_theme_stylebox_override("normal",plate(INK if primary else Color("#eee2c5"),Color("#a99e79")))
	b.add_theme_stylebox_override("hover",plate(Color("#52715d"),Color("#e8cb91")))
	b.add_theme_stylebox_override("pressed",plate(Color("#364f44"),Color("#e8cb91")))
	b.focus_mode=Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b

func panel(at: Vector2, size_:Vector2, color:Color) -> PanelContainer:
	var p:=PanelContainer.new()
	p.position=at
	p.size=size_
	p.add_theme_stylebox_override("panel",plate(color,Color("#b3ad8666"),4,12))
	hud.add_child(p)
	return p

func tool_icon(id:String) -> Texture2D:
	var shapes:={"hand":["    oo  ","  oo++o "," o++.+o "," o+.++o ","  o++o  ","   oo   "],"hoe":["   #### ","   ..## ","    +   ","   +    ","  +     "," +      "],"seed":["   oo   ","   ++   ","  o..o  "," o..+.o "," o.+..o ","  oooo  "],"can":["   ooo  "," o..+.o "," o....o+","  o..o +","  ++++  ","        "],"rod":["      +.","     + .","    +  .","   +   .","  +    o"," +      "]}
	var image:=Image.create_empty(16,12,false,Image.FORMAT_RGBA8)
	var palette:={"#":Color("#51696a"),".":Color("#6f9d91") if id=="can" else Color("#d0b387"),"+":Color("#856645"),"o":Color("#56634d")}
	for y in shapes[id].size():
		for x in shapes[id][y].length():
			var pixel:String=shapes[id][y][x]
			if pixel in palette: image.fill_rect(Rect2i(x*2,y*2,2,2),palette[pixel])
	return ImageTexture.create_from_image(image)

func equip(id:String) -> void:
	if id not in KIT: return
	if map.casting: finish_fishing(false)
	map.set_placement("")
	farm.s.tool=id
	map.update_spots()
	update_hud()

func start_fishing() -> void:
	if farm.s.tool!="rod":
		notify("水里有鱼影，换上竹竿（5）再抛竿。")
		return
	var reason:String=farm.cast_line()
	if reason!="":
		notify(reason)
		return
	persist()
	map.dest=map.hero
	map.route.clear()
	map.casting=true
	map.bite=false
	map.paused=true
	fishing_time=0.0
	bite_at=randf_range(1.5,3.1)
	notify("浮子已落水，等它沉下去。")
	sfx.note(320,0.14)

func finish_fishing(caught:bool) -> void:
	if not map.casting: return
	map.casting=false
	map.bite=false
	map.paused=false
	if caught:
		farm.s.bag.fish+=1
		persist()
		sfx.note(680,0.28,true)
		notify("竹篓里多了一尾河鲫。")
	else: notify("水线一松，收回了空钩。")

func make_hud() -> void:
	var top:=panel(Vector2(16,13),Vector2(310,46),Color("#223d35ef"))
	var bar:=HBoxContainer.new()
	bar.add_theme_constant_override("separation",14)
	top.add_child(bar)
	bar.add_child(lab("柳 汊",25,Color("#f8edcd"),true))
	clock_label=lab("",14,Color("#e8dcc0"))
	bar.add_child(clock_label)
	var tools:=panel(Vector2(720,13),Vector2(224,40),Color("#233d34ec"))
	var row:=HBoxContainer.new()
	tools.add_child(row)
	wallet=lab("",14,Color("#f7e3ac"))
	wallet.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(wallet)
	row.add_child(btn("托运簿",book))
	row.add_child(btn("设置",settings_page))
	var bottom:=panel(Vector2(16,465),Vector2(928,59),Color("#233c33f0"))
	var r:=HBoxContainer.new()
	r.add_theme_constant_override("separation",8)
	bottom.add_child(r)
	var vitals:=VBoxContainer.new()
	vitals.custom_minimum_size.x=96
	r.add_child(vitals)
	pack=lab("",14,CREAM)
	vitals.add_child(pack)
	energy_bar=ProgressBar.new()
	energy_bar.custom_minimum_size=Vector2(92,9)
	energy_bar.show_percentage=false
	energy_bar.max_value=farm.MAX_ENERGY
	var fill:=StyleBoxFlat.new()
	fill.bg_color=Color("#acc880")
	energy_bar.add_theme_stylebox_override("fill",fill)
	vitals.add_child(energy_bar)
	for i in KIT.size():
		var id:String=KIT.keys()[i]
		var pick:=btn("",func():equip(id))
		pick.icon=tool_icon(id)
		pick.custom_minimum_size.x=76
		pick.tooltip_text=str(i+1)+" · "+KIT[id]
		kit_buttons[id]=pick
		r.add_child(pick)
	hint=lab("",12,Color("#e3d4ad"))
	hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hint.clip_text=true
	r.add_child(hint)
	build_button=btn("营造",construction)
	r.add_child(build_button)
	r.add_child(btn("行囊",bag_page))
	toast=lab("",15,CREAM)
	toast.add_theme_stylebox_override("normal",plate(Color("#35493df0"),Color("#c6ba8c"),4,13))
	toast.position=Vector2(18,422)
	hud.add_child(toast)
	toast.hide()
	marker=lab("",13,CREAM)
	marker.add_theme_stylebox_override("normal",plate(Color("#263b33e6"),Color("#b8b27f88"),3,6))
	hud.add_child(marker)
	marker.hide()

func update_hud() -> void:
	var t:=int(farm.s.minutes)
	clock_label.text="%s　%s%02d　%02d:%02d　%s" % [map.ZONE_NAMES[farm.s.zone],farm.SEASONS[farm.season()],farm.season_day(),t/60,t%60,farm.weather(farm.s.day)]
	wallet.text="%d 文" % farm.s.coins
	build_button.text="收起工具" if map.placing!="" else "营造"
	hint.text="选格 · Esc 收起" if map.placing!="" else ("水量 %d/%d" % [farm.s.water,farm.capacity()] if farm.s.tool=="can" else "E 互动 · 右键行走")
	build_button.visible=farm.s.zone=="farm"
	pack.text="体力　%d/%d" % [farm.s.energy,farm.MAX_ENERGY]
	energy_bar.value=farm.s.energy
	for id in KIT:
		var pick:Button=kit_buttons[id]
		pick.text=KIT[id] if id!="seed" else farm.ITEMS[farm.s.crop].name
		pick.modulate=Color.WHITE if id==farm.s.tool else Color("#abae96")

func _process(dt: float) -> void:
	if not is_instance_valid(clock_label): return
	update_hud()
	if map.casting:
		fishing_time+=dt
		if not map.bite and fishing_time>=bite_at:
			map.bite=true
			sfx.note(830,0.23)
			notify("浮子沉了！点水面或按 E 收竿。",2)
		if fishing_time>=bite_at+2.0: finish_fishing(false)
	marker.visible=map.closest!="" and not map.paused
	if marker.visible:
		marker.text="E  "+map.caption(map.closest)
		if map.nearby.size()>1: marker.text+="　Tab 切换"
		marker.reset_size()
		marker.position=map.hero-Vector2(marker.size.x/2,64)
	if notice_time>0:
		notice_time-=dt
		if notice_time<=0: toast.hide()

func notify(message:String, duration:=5.0) -> void:
	toast.text=message
	toast.reset_size()
	toast.visible=true
	notice_time=duration

func persist() -> void:
	farm.s.location=[map.hero.x,map.hero.y]
	if not farm.save_to(save_path): notify("存档写入失败，请检查本机存储。",12)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(clock_label):
		persist()

func _unhandled_input(event:InputEvent) -> void:
	if map.casting:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode==KEY_ESCAPE: finish_fishing(false)
			elif event.physical_keycode in [KEY_E,KEY_SPACE]: finish_fishing(map.bite)
		elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			finish_fishing(map.bite)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if is_instance_valid(popup): close_sheet()
			elif map.placing!="": map.set_placement("")
			return
		if is_instance_valid(popup): return
		if event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_5:
			equip(KIT.keys()[event.physical_keycode-KEY_1])
			return
		match event.physical_keycode:
			KEY_TAB: map.cycle_focus()
			KEY_E,KEY_SPACE:
				if map.closest!="" and map.spots.has(map.closest) and map.in_reach(map.closest):
					map.target=""
					map.route.clear()
					map.dest=map.hero
					interact(map.closest)
			KEY_B: bag_page()
			KEY_J: book()
	if not is_instance_valid(popup) and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		map.point(event.position)
	if not is_instance_valid(popup) and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		map.target=""
		map.dest=map.area(event.position)
		map.goal=Vector2.INF
		map.route.clear()

func close_sheet() -> void:
	epoch+=1
	if is_instance_valid(popup):
		hud.remove_child(popup)
		popup.queue_free()
	popup=null
	map.paused=false
	map.dest=map.hero
	map.target=""
	map.route.clear()
	map.goal=Vector2.INF
	page=""

func sheet(title:String, id:String) -> void:
	if map.casting: finish_fishing(false)
	close_sheet()
	map.set_placement("")
	page=id
	map.paused=true
	popup=ColorRect.new()
	popup.color=Color("#13251f60")
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(popup)
	var paper:=PanelContainer.new()
	paper.position=Vector2(448,67)
	paper.size=Vector2(492,409)
	paper.add_theme_stylebox_override("panel",plate(CREAM,Color("#bba978"),6,18))
	popup.add_child(paper)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",7)
	paper.add_child(col)
	var head:=HBoxContainer.new()
	col.add_child(head)
	sheet_title=lab(title,24,INK,true)
	sheet_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(sheet_title)
	head.add_child(btn("返回",close_sheet))
	col.add_child(HSeparator.new())
	scroll=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	content=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",9)
	scroll.add_child(content)

func para(words:String, px:=15) -> Label:
	var l:=lab(words,px)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l

func line_input(placeholder:String) -> LineEdit:
	var field:=LineEdit.new()
	field.placeholder_text=placeholder
	field.add_theme_font_override("font",ui_font)
	field.add_theme_font_size_override("font_size",15)
	field.add_theme_color_override("font_color",INK)
	field.add_theme_color_override("font_placeholder_color",Color("#777f6d"))
	field.add_theme_stylebox_override("normal",plate(Color("#fff9e9"),Color("#a1a589"),3))
	field.max_length=400
	content.add_child(field)
	return field

func action(caption:String,fn:Callable,primary:=false) -> void:
	content.add_child(btn(caption,fn,primary))

func interact(id:String) -> void:
	if is_instance_valid(popup): return
	if map.placing!="":
		if map.placing=="reclaim":
			var site:int=-1
			if id.begins_with("plot"): site=farm.s.plots[int(id.trim_prefix("plot"))].site
			elif id.begins_with("chest"): site=int(id.trim_prefix("chest"))
			elif id!="box": return
			notify(farm.reclaim(site))
			map.refresh_navigation()
			map.set_placement("")
			persist()
			return
		if id.begins_with("site"):
			var site:=int(id.trim_prefix("site"))
			var was_free:bool=farm.free_site(site)
			var message:String=farm.build(map.placing,site)
			if was_free and not farm.free_site(site):
				sfx.note(270,0.22)
				map.refresh_navigation()
				map.hero=map.area(map.hero)
				map.set_placement("")
				persist()
			notify(message)
		return
	if id in ["east","west"]:
		var zones:=["farm","market","marsh"]
		var next:int=zones.find(farm.s.zone)+(1 if id=="east" else -1)
		if next>=0 and next<zones.size():
			var zone:String=zones[next]
			var entry:Vector2=map.LOCATIONS[zone]["west" if id=="east" else "east"]
			map.travel(zone,entry+Vector2(40 if id=="east" else -40,4))
			farm.later(5)
			persist()
			notify(map.ZONE_NAMES[zone],2)
		return
	if id.begins_with("site") and farm.s.tool=="hoe":
		var site:=int(id.trim_prefix("site"))
		notify(farm.clear_brush(site) if farm.has_brush(site) else farm.build("field",site))
		map.flourish("hoe")
		persist()
		return
	if id.begins_with("chest"):
		box_page()
		return
	if id.begins_with("plot"):
		var msg:String=farm.work_plot(int(id.trim_prefix("plot")))
		map.flourish(farm.s.tool)
		sfx.note(490,0.16)
		notify(msg)
		persist()
		return
	match id:
		"board":
			sheet("街坊托单","board")
			var job:Dictionary=farm.market_request()
			para("%s想%s。" % [farm.PEOPLE[job.person],job.use])
			var reward:int=job.quantity*(farm.ITEMS[job.item].price+1)+2
			para("%s × %d　·　酬谢 %d 文　·　今日有效" % [farm.ITEMS[job.item].name,job.quantity,reward])
			if farm.s.delivery_day==farm.s.day: para("今日这份心意已送到。")
			else:
				action("从背篓交货",func():
					var msg:String=farm.deliver_request()
					persist()
					close_sheet()
					notify(msg),true)
		"angler","bank": start_fishing()
		"greens_a","greens_b":
			notify(farm.forage(id))
			persist()
		"well":
			farm.s.water=farm.capacity()
			sfx.note(490,0.16)
			notify("井水装满一壶，够浇 %d 畦。" % farm.capacity())
			persist()
		"wood":
			notify(farm.gather())
			sfx.note(250,0.15)
			persist()
		"box": box_page()
		"home":
			map.travel("house",Vector2(490,378))
			persist()
			notify("家里　·　左边是床，右边是灶和竹篮。",3)
		"outside":
			map.travel("farm",Vector2(235,224))
			persist()
		"bed","pantry": home()
		"stove":
			sheet("青砖灶台","stove")
			para("马兰鲫鱼汤　　河鲫 ×1　马兰头 ×1")
			para("灶边竹篮和背篓的食材都可以下锅，趁热喝下可恢复 22 点体力。")
			action("起火煮汤",func():
				var msg:String=farm.cook()
				persist()
				close_sheet()
				notify(msg),true)
		"dock":
			sheet("柳下渡口","dock")
			para("船板已补 %d / 8。%s" % [farm.s.boat,ferry_line()])
			if farm.early_market():
				action("搭早渡到芦湾钓台",func():
					close_sheet()
					map.travel("marsh",map.LOCATIONS.marsh.angler-Vector2(16,0))
					farm.later(1)
					persist()
					sfx.note(720,0.6,true),true)
			action("去找周叔",func():npc_page("fisher"))
		"shop","carpenter","fisher": npc_page(id)

func ferry_line() -> String:
	if farm.s.boat<8: return "晴日能听见木匠的锤声。"
	return "逢双日清晨开渡，铜铃随水声轻晃。" if farm.s.ferry else "船已下水，周叔准备逢双日开渡。"

func construction() -> void:
	if map.placing!="":
		map.set_placement("")
		return
	sheet("院里营造","construction")
	var empty:int=farm.YARD_COLS*farm.YARD_ROWS-farm.s.plots.size()-farm.s.chests.size()
	para("菜畦 %d 块　·　空草地 %d 块" % [farm.s.plots.size(),empty])
	if empty==0:
		para("这片院地已用满。")
	for kind in farm.BUILD:
		if empty==0: break
		var spec:Dictionary=farm.BUILD[kind]
		var cost:="木料 %d 份 · " % spec.wood if spec.wood else ""
		action("%s　%s%d 分钟" % [spec.name,cost,spec.minutes],func():
			close_sheet()
			map.set_placement(kind)
			notify("点院内草地选址建"+spec.name+"。"))
	if farm.s.legacy_box or not farm.s.plots.is_empty() or not farm.s.chests.is_empty():
		action("平整空畦 / 拆收出货箱",func():
			close_sheet()
			map.set_placement("reclaim")
			notify("选择空畦或出货箱。箱板会退回背篓。"))
	para("各处出货箱共用晚船货单。背篓中有木料 %d 份。" % farm.s.bag.wood,14)

func home() -> void:
	sheet("姨婆的农舍","home")
	para("灶边竹篮　"+farm.inventory(farm.s.pantry))
	if farm.inventory(farm.s.pantry)!="空":
		action("把竹篮里的收成装进背篓",func():
			for k in farm.ITEMS:
				farm.s.bag[k]+=farm.s.pantry[k]
				farm.s.pantry[k]=0
			persist()
			home())
	para("今晚出货预计 %d 文。睡一觉，次日清晨在家门口醒来。" % farm.dispatch_plan().coins)
	action("收工，睡到明早",sleep_night,true)
	action("翻看这几天的账",history_page)

func sleep_night() -> void:
	var previous:bool=farm.s.ferry
	var receipt:String=farm.night()
	map.clock=0
	map.travel("farm",Vector2(235,220))
	persist()
	close_sheet()
	sfx.note(780 if farm.s.ferry and not previous else 520,1.0,true)
	notify("早安。昨晚"+receipt+"。",9)

func box_page() -> void:
	sheet("河埠出货箱","box")
	para("箱中　"+farm.inventory(farm.s.box))
	para("背篓　"+farm.inventory(farm.s.bag))
	action("将背篓货物装箱",func():
		var msg:String=farm.deposit()
		persist()
		box_page()
		para(msg),true)
	action("翻开托运簿",book)
	para("每天收工时结算。今晚预计收到 %d 文。" % farm.dispatch_plan().coins)

func bag_page() -> void:
	sheet("竹编行囊","bag")
	para("背篓　"+farm.inventory(farm.s.bag))
	para("本季种袋 · "+farm.SEASONS[farm.season()])
	for k in farm.FIELDS:
		if farm.season() not in farm.CROPS[k] and farm.s.seeds[k]<=0: continue
		var select=func():
			farm.s.crop=k
			equip("seed")
			persist()
			bag_page()
		action("%s　%d 粒%s" % [farm.ITEMS[k].name,farm.s.seeds[k],"　· 已选" if farm.s.crop==k else ""],select)
	for k in farm.ITEMS:
		if k not in ["wood","fish"] and farm.s.bag[k]>0:
			action("吃一份"+farm.ITEMS[k].name,func():
				var msg:String=farm.eat(k)
				persist()
				bag_page()
				para(msg))
	action("查看收支和镇上近况",history_page)

func history_page() -> void:
	sheet("生活手记","history")
	para("%s · 明日%s　　%s" % [farm.SEASONS[farm.season()],farm.weather(farm.s.day+1),ferry_line()],14)
	if not farm.s.last_shipment.is_empty(): action("查上一班晚船的实收单",func():show_bill(farm.s.last_shipment))
	if farm.s.log.is_empty(): para("今天刚到柳汊。第一笔出货会记在这里。")
	var entries:Array=farm.s.log.duplicate()
	entries.reverse()
	for entry in entries: para(entry,14)

func book() -> void:
	sheet("渡口托运簿","book")
	para("每晚默认全数出货。单个物品的约定优先于整类。",14)
	for key in farm.s.rules:
		var r:Dictionary=farm.s.rules[key]
		action(farm.describe(r)+"　×",func():rule_preview({"selector":key,"action":"remove","count":0}))
	var field:=line_input("例如：每晚每种菜留两份，其余卖掉")
	if not clerk_thread.is_empty(): para("先生上次问：「"+str(clerk_thread.back())+"」",14)
	var send=func(): ask_clerk(field.text.strip_edges())
	field.text_submitted.connect(func(_v):send.call())
	action("请账房先生拟约",send,true)
	action("按项目填托运单",manual_rule)
	action("查看今晚试算",func():show_bill(farm.dispatch_plan()))

func show_bill(bill:Dictionary) -> void:
	sheet("第 %d 日 · 晚船回单" % bill.day if bill.has("day") else "今晚的出货单","preview")
	para("卖出　"+farm.inventory(bill.sold))
	para("留在灶边　"+farm.inventory(bill.kept))
	para("送往工坊　"+farm.inventory(bill.sent))
	para(("实收入账　%d 文" if bill.has("day") else "预计入账　%d 文") % bill.coins)
	action("回托运簿",book)

func ask_clerk(words:String) -> void:
	if words=="": return
	if ai.busy:
		para("上一封回信还在路上，请稍后再递。")
		return
	var version:=epoch
	para("先生正在看托运单……")
	var context_words:=words if clerk_thread.is_empty() else "\n".join(clerk_thread)+"\n玩家："+words
	var raw:Dictionary=await ai.clerk(farm,context_words)
	if version!=epoch: return
	if raw.has("error"):
		book()
		para(str(raw.error))
	elif raw.has("question"):
		clerk_thread.append(words)
		clerk_thread.append(str(raw.question).left(180))
		if clerk_thread.size()>6: clerk_thread=clerk_thread.slice(-6)
		book()
	else: rule_preview(raw)

func rule_preview(raw:Dictionary) -> void:
	var r:Dictionary=farm.validate(raw)
	if r.has("error"):
		book()
		para(r.error)
		return
	preview=r
	sheet("核对约定","rule")
	para(farm.describe(r)+"。",20)
	var shadow=Farm.new()
	shadow.s=farm.s.duplicate(true)
	shadow.set_rule(r)
	var bill:Dictionary=shadow.dispatch_plan()
	para("按现在这箱货试算：卖 "+farm.inventory(bill.sold)+"，家留 "+farm.inventory(bill.kept)+"，送工坊 "+farm.inventory(bill.sent)+"。")
	action("记入托运簿",func():
		var msg:String=farm.set_rule(preview)
		clerk_thread.clear()
		persist()
		book()
		para(msg),true)
	action("再想想",book)

func manual_rule() -> void:
	sheet("填写托运单","form")
	para("对象")
	var selector:=OptionButton.new()
	selector.add_theme_font_override("font",ui_font)
	var ids:Array=["vegetable"]+farm.ITEMS.keys()
	for id in ids: selector.add_item(farm.label_for(id))
	content.add_child(selector)
	var choice:=OptionButton.new()
	choice.add_theme_font_override("font",ui_font)
	for name_ in ["留在家里","全部卖出","送往工坊"]: choice.add_item(name_)
	content.add_child(choice)
	var amount:=SpinBox.new()
	amount.min_value=1
	amount.max_value=999
	amount.value=2
	content.add_child(amount)
	action("核对这项约定",func():rule_preview({"selector":ids[selector.selected],"action":["keep","sell","workshop"][choice.selected],"count":int(amount.value)}),true)

func npc_page(id:String) -> void:
	npc=id
	sheet(farm.PEOPLE[id],"npc")
	match id:
		"shop":
			para("红布菜铺　·　已收到镇上鲜菜 %d 份" % farm.s.sold_veg)
			para("「早市有人问头茬菜呢。」" if farm.s.sold_veg<8 else "「昨日的菜有人回头来买，我把门口的空筐也摆上啦。」")
			var row:=HBoxContainer.new()
			content.add_child(row)
			if farm.s.minutes>=1080: para("今日收摊，明早七时开铺。")
			for k in farm.FIELDS:
				if farm.season() not in farm.CROPS[k] or farm.s.minutes>=1080: continue
				row.add_child(btn("%s种 ×%d · 2文" % [farm.ITEMS[k].name,4 if farm.s.friendship.get("shop",0)>=4 else 3],func():
					var msg:String=farm.buy_seed(k)
					persist()
					npc_page(id)
					para(msg)))
			if farm.early_market():
				action("早渡鱼市 · 卖出背篓河鲫　8 文/尾",func():
					var msg:String=farm.trade_fish()
					persist()
					npc_page(id)
					para(msg))
		"carpenter":
			para("河岸修船　·　船板 %d / 8" % farm.s.boat)
			if farm.s.can_level==0:
				action("给水壶换大水胆　18 文 · 木料 2",func():
					var msg:String=farm.improve_can()
					persist()
					npc_page(id)
					para(msg))
			para("「舷边补好了，还差一层桐油香。」" if farm.s.boat>=8 else "「你听，这块板敲起来还发闷。晴天再补一块。」")
			if farm.s.boat<8 and not farm.s.boat_agreed:
				action("商量把拾来的木料送工坊",func():
					farm.s.boat_agreed=true
					farm.log_line("陆木匠答应收修船的木料，船修好便停。")
					persist()
					npc_page(id)
					para("「成。我收木料，你在托运簿上记下要送几份就好。」"))
			elif farm.s.boat_agreed and farm.s.boat<8: action("约好收料了，去写托运单",book)
		"fisher":
			para("柳下渡口　·　"+ferry_line())
			para("「隔日撑一趟就好。剩下的早晨，我给闺女煮碗面。」")
	para("往来情分　%d" % farm.s.friendship.get(id,0),14)
	if farm.s.gifts.get(id,0)!=farm.s.day and farm.inventory(farm.s.bag)!="空":
		action("从背篓里送份心意",func():
			sheet("送给"+farm.PEOPLE[id],"gift")
			for k in farm.ITEMS:
				if farm.s.bag[k]>0:
					action("%s × 1" % farm.ITEMS[k].name,func():
						var msg:String=farm.give(id,k)
						persist()
						npc_page(id)
						para(msg)))
	var history:Array=farm.s.talk.get(id,[])
	if not history.is_empty():
		for turn in history.slice(-2):
			para("你："+turn.player+"\n"+farm.PEOPLE[id]+"："+turn.reply,14)
	var field:=line_input("和"+farm.PEOPLE[id]+"聊一句…")
	var send=func(): chat(id,field.text.strip_edges())
	field.text_submitted.connect(func(_v):send.call())
	action("说给对方听",send,true)

func chat(id:String, words:String) -> void:
	if words.is_empty(): return
	if ai.busy:
		para("上一封回信还在路上，请稍后再聊。")
		return
	var version:=epoch
	para("对方想了想……")
	var answer:Dictionary=await ai.speak(farm,id,words)
	if epoch!=version: return
	if answer.has("error") or not answer.get("line","") is String or str(answer.get("line","")).strip_edges()=="":
		npc_page(id)
		para(str(answer.get("error","没有听清，请再说一次。")))
		return
	if not farm.s.talk.has(id): farm.s.talk[id]=[]
	farm.s.talk[id].append({"player":words,"reply":answer.line.strip_edges().left(300)})
	if farm.s.talk[id].size()>12: farm.s.talk[id].pop_front()
	if id=="carpenter" and answer.get("accept_wood",false)==true and farm.s.boat<8 and not farm.s.boat_agreed:
		farm.s.boat_agreed=true
		farm.log_line("陆木匠在交谈中同意收料。")
	farm.later(8)
	persist()
	npc_page(id)

const MODEL_ROLES={"default":"全镇默认","clerk":"账房先生","shop":"阿禾","carpenter":"陆木匠","fisher":"周叔"}

func model_select(captions:Array, selected:int) -> OptionButton:
	var pick:=OptionButton.new()
	pick.add_theme_font_override("font",ui_font)
	for caption in captions: pick.add_item(caption)
	if selected>=0: pick.select(selected)
	content.add_child(pick)
	return pick

func edit_model(role:String, provider:="", reset:=false) -> void:
	var profiles=ai.profiles
	var active:Dictionary=profiles.profile(role)
	var p:Dictionary=profiles.preset(provider) if reset else active
	sheet("模型 · "+MODEL_ROLES[role],"model")
	if role!="default":
		para("当前沿用全镇默认" if profiles.inherits(role) else "当前使用单独配置",14)
		if not profiles.inherits(role):
			action("恢复全镇默认",func():
				if profiles.inherit(role): settings_page()
				else: para("配置文件写入失败。"))
	para("服务商 / 接口协议",13)
	var ids:Array=profiles.catalog.keys()
	var labels:=[]
	for id in ids: labels.append(profiles.catalog[id].label)
	var provider_pick:=model_select(labels,ids.find(p.id))
	provider_pick.item_selected.connect(func(i): edit_model(role,ids[i],true))
	var models:Array=profiles.catalog[p.id].models
	para("模型 ID",13)
	var model_list:OptionButton
	if not models.is_empty():
		var choices:Array=models.duplicate()
		choices.append("手动填写…")
		model_list=model_select(choices,models.find(p.model) if p.model in models else models.size())
	var name_:=line_input("填写模型 ID")
	name_.text=p.model
	if model_list:
		model_list.item_selected.connect(func(i):
			if i<models.size(): name_.text=models[i]
			else: name_.grab_focus())
		name_.text_changed.connect(func(v): model_list.select(models.find(v) if v in models else models.size()))
	para("完整接口地址",13)
	var url:=line_input("https://…")
	url.text=p.endpoint
	var key:=line_input("API 密钥 · 留空沿用该地址的凭证")
	key.secret=true
	var remember:=CheckBox.new()
	remember.text="在此 Windows 账户记住密钥"
	remember.add_theme_font_override("font",ui_font)
	remember.add_theme_color_override("font_color",INK)
	remember.visible=OS.get_name()=="Windows"
	remember.button_pressed=profiles.remembered(url.text)
	content.add_child(remember)
	url.text_changed.connect(func(v):
		key.clear()
		remember.button_pressed=profiles.remembered(v.strip_edges()))
	var auths:=["bearer","x-api-key","none"]
	para("身份验证",13)
	var auth:=model_select(["Bearer Token","x-api-key","无需密钥"],auths.find(p.auth))
	var outputs:=["json","tools"]
	para("账房拟约格式",13)
	var output:=model_select(["JSON 文本","工具调用"],outputs.find(p.output))
	var draft:=func(): return {"id":p.id,"endpoint":url.text.strip_edges(),"model":name_.text.strip_edges(),"auth":auths[auth.selected],"output":outputs[output.selected]}
	var row:=HBoxContainer.new()
	content.add_child(row)
	var status:=para("",14)
	var version:=epoch
	row.add_child(btn("测试连接",func():
		var submitted:Dictionary=draft.call()
		status.text="正在测试 "+submitted.model+"…"
		var result:Dictionary=await ai.probe(submitted,key.text.strip_edges(),role)
		if version==epoch: status.text=str(result.get("error",submitted.model+" 测试通过。"))))
	row.add_child(btn("保存并使用",func():
		var error:String=profiles.save(role,draft.call(),key.text.strip_edges(),remember.button_pressed)
		if error!="": status.text=error
		else:
			settings_page()
			notify(MODEL_ROLES[role]+"的模型设置已保存。"),true))
	row.add_child(btn("清除此地址密钥",func():
		if profiles.forget(url.text.strip_edges()):
			key.clear()
			remember.button_pressed=false
			status.text="已清除这个地址在柳汊保存的密钥。"
		else: status.text="密钥未能清除。"))

func settings_page() -> void:
	sheet("来信与声音","settings")
	para("模型设置",17)
	for role in MODEL_ROLES:
		var p:Dictionary=ai.profiles.profile(role)
		var prefix:String="沿用 · " if ai.profiles.inherits(role) else ""
		action(MODEL_ROLES[role]+"　"+prefix+p.model,func(): edit_model(role))
	action("切换音效",func():
		sfx.volume_db=0 if sfx.volume_db < -40 else -80
		notify("音效已开" if sfx.volume_db==0 else "音效已关"))
	action("制作与许可",func():
		sheet("制作与许可","credits")
		para("柳汊 · 早渡。场景底图使用 imagegen 生成。")
		para(Engine.get_license_text(),13)
		for part in Engine.get_copyright_info():
			para(part.name,14)
			for component in part.parts:
				para("\n".join(component.copyright)+"\n"+component.license,12)
		var licenses:=Engine.get_license_info()
		for title in licenses:
			para(title+"\n"+licenses[title],12))
