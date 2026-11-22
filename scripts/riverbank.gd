extends Node2D

signal arrived(key: String)
signal day_ended
const ZONE_NAMES={"farm":"春畦小院","market":"柳汊镇街","marsh":"芦湾浅滩","house":"姨婆家"}
const LOCATIONS={
	"farm":{"home":Vector2(235,210),"box":Vector2(325,220),"well":Vector2(515,224),"wood":Vector2(826,222),"east":Vector2(911,265)},
	"market":{"west":Vector2(50,270),"east":Vector2(911,274),"dock":Vector2(778,379),"board":Vector2(325,282)},
	"marsh":{"west":Vector2(50,270),"greens_a":Vector2(282,262),"greens_b":Vector2(542,305),"angler":Vector2(696,347)},
	"house":{"bed":Vector2(223,243),"stove":Vector2(709,211),"pantry":Vector2(736,333),"outside":Vector2(472,428)}
}
const WALKWAYS={
	"farm":[Rect2(37,219,887,172),Rect2(190,194,128,58),Rect2(475,199,87,53)],
	"market":[Rect2(40,242,884,139),Rect2(155,199,115,60),Rect2(473,183,138,81),Rect2(752,201,147,64)],
	"marsh":[Rect2(38,232,595,94),Rect2(214,202,316,70),Rect2(510,262,218,74),Rect2(651,288,85,72)],
	"house":[Rect2(184,221,634,197),Rect2(652,195,110,82),Rect2(455,379,79,75)]
}
const FIXTURES={
	"farm":[Rect2(493,186,40,28)],
	"market":[Rect2(211,265,79,19),Rect2(311,271,29,12)],
	"marsh":[Rect2(322,205,28,16)],
	"house":[Rect2(173,298,36,82),Rect2(795,264,38,122)]
}
const NAMES = {"home":"回屋歇息","box":"出货箱","shop":"阿禾的小铺","wood":"拾木料","dock":"旧渡口","carpenter":"陆木匠","fisher":"周叔","well":"井边汲水","angler":"抛竿","greens_a":"采马兰头","greens_b":"采马兰头"}
const BARNS = {"carpenter":Color("#9b6749"),"shop":Color("#bc6452"),"fisher":Color("#536e76")}
var farm
var hero:=Vector2(280,252)
var dest:=hero
var target:=""
var heading:=1
var facing:=1
var walking:=false
var paused:=false
var anim:=0.0
var clock:=0.0
var spots: Dictionary={}
var closest:=""
var positions: Dictionary={}
var font: Font
var placing:=""
var backdrop:=Sprite2D.new()
var nav:=AStarGrid2D.new()
var route:=PackedVector2Array()
var goal:=Vector2.INF
var casting:=false
var bite:=false
var swing:=0.0
var swing_tool:=""

func flourish(tool:String) -> void:
	swing=0.35
	swing_tool=tool

func travel(zone:String,spawn:Vector2) -> void:
	farm.s.zone=zone
	var files:Dictionary={"farm":"res://assets/homestead.png","market":"res://assets/village.png","marsh":"res://assets/reedbank.png","house":"res://assets/interior.png"}
	backdrop.texture=load(files[zone])
	backdrop.scale=Vector2(960,540)/backdrop.texture.get_size()
	nav.region=Rect2i(0,0,96,54)
	nav.cell_size=Vector2(10,10)
	nav.offset=Vector2(5,5)
	nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for y in 54:
		for x in 96:
			var cell:=Vector2i(x,y)
			nav.set_point_solid(cell,not walkable(nav.get_point_position(cell)))
	hero=area(spawn)
	positions.clear()
	if zone=="market":
		for id in BARNS: positions[id]=npc_dest(id)
	set_placement("")

func walkable(p:Vector2) -> bool:
	for fixture:Rect2 in FIXTURES[farm.s.zone]:
		if fixture.has_point(p): return false
	for rect_:Rect2 in WALKWAYS[farm.s.zone]:
		if rect_.has_point(p): return true
	return false

func site_position(site:int) -> Vector2:
	if site>=18: return Vector2(541+((site-18)%5)*70,286+floori((site-18)/5.0)*40)
	return Vector2(121+(site%farm.YARD_COLS)*70,286+floori(float(site)/farm.YARD_COLS)*40)

func bed(i: int) -> Vector2:
	return site_position(farm.s.plots[i].site)

func set_placement(kind:String) -> void:
	placing=kind
	target=""
	closest=""
	dest=hero
	route.clear()
	goal=Vector2.INF
	update_spots()

func update_spots() -> void:
	spots.clear()
	if placing!="" or (farm.s.tool=="hoe" and farm.s.zone=="farm"):
		for site in farm.YARD_SITES:
			if farm.free_site(site): spots["site"+str(site)]=site_position(site)
		if placing!="": return
	spots.merge(LOCATIONS[farm.s.zone])
	spots.merge(positions,true)
	if farm.s.zone!="farm": return
	for i in farm.s.plots.size(): spots["plot"+str(i)]=bed(i)
	for site in farm.s.chests: spots["chest"+str(site)]=site_position(site)

func _ready() -> void:
	font=ThemeDB.fallback_font
	backdrop.centered=false
	backdrop.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	backdrop.show_behind_parent=true
	add_child(backdrop)
	var zone:String=farm.s.zone if farm.s.zone in ZONE_NAMES else "farm"
	var spawn:=Vector2(280,252) if zone=="farm" else Vector2(95,275)
	var saved=farm.s.get("location",[])
	if saved is Array and saved.size()==2: spawn=Vector2(saved[0],saved[1])
	travel(zone,spawn)
	set_process(true)

func area(p: Vector2) -> Vector2:
	var best:=Vector2.INF
	for rect_:Rect2 in WALKWAYS[farm.s.zone]:
		var near:=p.clamp(rect_.position+Vector2.ONE,rect_.end-Vector2.ONE)
		if near.distance_squared_to(p)<best.distance_squared_to(p): best=near
	if not walkable(best):
		var cell:=grid_cell(best)
		if not nav.is_point_solid(cell): return nav.get_point_position(cell)
		for radius in range(2,10):
			for dy in range(-radius,radius+1):
				for dx in range(-radius,radius+1):
					var other:=cell+Vector2i(dx,dy)
					if nav.is_in_boundsv(other) and not nav.is_point_solid(other): return nav.get_point_position(other)
	return best

func grid_cell(p:Vector2) -> Vector2i:
	var cell:=Vector2i(p/10)
	if not nav.is_point_solid(cell): return cell
	for dy in [-1,0,1]:
		for dx in [-1,0,1]:
			var neighbor:=cell+Vector2i(dx,dy)
			if nav.is_in_boundsv(neighbor) and not nav.is_point_solid(neighbor): return neighbor
	return cell

func npc_dest(id: String) -> Vector2:
	var noon_: bool=farm.s.minutes>=720
	var late_: bool=farm.s.minutes>=960
	match id:
		"carpenter": return Vector2(823,227) if late_ else (Vector2(805,348) if noon_ else Vector2(841,254))
		"fisher": return Vector2(720,360) if not (farm.s.day%2==0 and noon_) else Vector2(638,313)
	return Vector2(570,217) if not late_ else Vector2(562,240)

func _process(dt: float) -> void:
	if farm==null: return
	anim+=dt
	swing=maxf(0,swing-dt)
	for id in (BARNS.keys() if farm.s.zone=="market" else []):
		if not positions.has(id): positions[id]=npc_dest(id)
		if not paused: positions[id]=positions[id].move_toward(npc_dest(id),dt*20)
	update_spots()
	walking=false
	if not paused:
		clock+=dt
		if clock>4:
			clock=0
			farm.later(5)
		if farm.s.minutes>=1320:
			day_ended.emit()
			return
		var dir:=Vector2(Input.get_axis("ui_left","ui_right"),Input.get_axis("ui_up","ui_down"))
		dir+=Vector2(int(Input.is_physical_key_pressed(KEY_D))-int(Input.is_physical_key_pressed(KEY_A)),int(Input.is_physical_key_pressed(KEY_S))-int(Input.is_physical_key_pressed(KEY_W)))
		var last:=hero
		if dir.length_squared()>0:
			target=""
			var motion:=dir.normalized()*dt*152
			if walkable(hero+Vector2(motion.x,0)): hero.x+=motion.x
			if walkable(hero+Vector2(0,motion.y)): hero.y+=motion.y
			for gate in ["west","east","outside"]:
				if gate not in LOCATIONS[farm.s.zone] or placing!="": continue
				var entrance:Vector2=LOCATIONS[farm.s.zone][gate]
				var crossing:bool=(gate=="west" and dir.x<0 and hero.x<=entrance.x) or (gate=="east" and dir.x>0 and hero.x>=entrance.x) or (gate=="outside" and dir.y>0 and hero.y>=entrance.y)
				if crossing and hero.distance_to(entrance)<26:
					arrived.emit(gate)
					return
			dest=hero
			goal=Vector2.INF
			route.clear()
		else:
			if spots.has(target): dest=area(spots[target]+Vector2(0,10))
			if hero.distance_to(dest)>1 and dest.distance_to(goal)>2:
				goal=dest
				route=nav.get_point_path(grid_cell(hero),grid_cell(dest))
				if not route.is_empty():
					route.remove_at(0)
					route.append(dest)
			if not route.is_empty():
				hero=hero.move_toward(route[0],dt*165)
				if hero.distance_to(route[0])<0.2: route.remove_at(0)
		walking=last.distance_to(hero)>0.05
		if walking:
			if absf(last.x-hero.x)>0.1: heading=1 if hero.x>last.x else -1
			facing=1 if hero.y>=last.y else -1
		if not target.is_empty() and hero.distance_to(dest)<2:
			var done:=target
			target=""
			arrived.emit(done)
	closest=""
	var distance:=49.0
	for id in spots:
		var d:float=hero.distance_to(spots[id])
		if d<distance:
			closest=id
			distance=d
	queue_redraw()

func point(at: Vector2) -> void:
	if paused: return
	var pick:=""
	var score:=1000.0
	for id in spots:
		var ground:bool=id.begins_with("plot") or id.begins_with("site")
		var offset:=Vector2.ZERO if ground else Vector2(0,-11)
		var d=at.distance_to(spots[id]+offset)
		var radius:=33 if ground else 30
		if d<radius and d<score:
			pick=id
			score=d
	if pick=="" and placing=="":
		if farm.s.zone=="house":
			if Rect2(88,90,246,150).has_point(at): pick="bed"
			elif Rect2(603,69,193,154).has_point(at): pick="stove"
			elif Rect2(734,203,174,183).has_point(at): pick="pantry"
		if farm.s.zone=="farm" and Rect2(142,106,126,94).has_point(at): pick="home"
		if farm.s.zone=="farm" and Rect2(772,102,118,98).has_point(at): pick="wood"
		if farm.s.zone=="farm" and Rect2(483,168,62,58).has_point(at): pick="well"
		if farm.s.zone=="marsh" and (Rect2(655,307,93,101).has_point(at) or (farm.s.tool=="rod" and at.y>372)): pick="angler"
		if farm.s.zone=="market":
			if Rect2(206,232,138,54).has_point(at): pick="board"
			if Rect2(460,92,153,100).has_point(at): pick="shop"
			elif Rect2(725,382,116,66).has_point(at): pick="dock"
	target=pick
	dest=area(at) if pick.is_empty() else area(spots[pick]+Vector2(0,10))
	goal=Vector2.INF

func caption(id: String) -> String:
	match id:
		"board": return "街坊托单"
		"bed": return "歇息"
		"stove": return "起灶煮汤"
		"pantry": return "灶边竹篮"
		"outside": return "出门"
	if id=="west": return "回小院" if farm.s.zone=="market" else "回镇街"
	if id=="east": return "去镇街" if farm.s.zone=="farm" else "去芦湾"
	if id.begins_with("site") and placing!="": return "建"+farm.BUILD[placing].name
	if id.begins_with("site"): return "清理枯枝" if farm.has_brush(int(id.trim_prefix("site"))) else "挥锄开畦"
	if id.begins_with("chest"): return "田头出货箱"
	if id.begins_with("plot"):
		var p:Dictionary=farm.s.plots[int(id.trim_prefix("plot"))]
		if p.item=="": return "空畦 · "+("湿" if p.wet else "干")
		if p.age>=farm.GROWTH[p.item]: return "可收 · "+farm.ITEMS[p.item].name
		return farm.ITEMS[p.item].name+(" · 湿" if p.wet else " · 待浇")
	return NAMES.get(id,"")

func rect(p: Vector2, size_: Vector2, color: String) -> void:
	draw_rect(Rect2(p.round(),size_),Color(color))
func block(x: float,y: float,w: float,h: float,c: String) -> void:
	rect(Vector2(x,y),Vector2(w,h),c)

func person(p: Vector2, coat: Color, is_hero: bool, straw: bool=false) -> void:
	var x:=roundf(p.x)
	var y:=roundf(p.y)
	var step:=0 if not is_hero or not walking else roundi(sin(anim*17)*2)
	draw_set_transform(Vector2(x,y),0,Vector2(1,0.35))
	draw_circle(Vector2(0,-1),10,Color("#43544370"))
	draw_set_transform(Vector2.ZERO)
	var side:=heading if is_hero else -1
	draw_set_transform(Vector2(x,y),0,Vector2(side,1))
	block(-6,-9,5,8+step,"434a42")
	block(2,-9,5,8-step,"4d554b")
	block(-7,-2+step,7,2,"323d37")
	block(2,-2-step,7,2,"323d37")
	block(-7,-19,14,11,"3c4b41")
	draw_rect(Rect2(-6,-20,11,11),coat)
	draw_rect(Rect2(-8,-17,5,7),coat.lightened(0.16))
	draw_rect(Rect2(4,-17,4,7),coat.darkened(0.15))
	block(-8,-11,4,3,"d6a36e")
	block(6,-11,3,3,"e6bc88")
	block(-6,-9,13,3,"686449")
	block(-2,-20,6,2,"ebd7aa")
	block(0,-18,2,3,"c2ad83")
	block(-5,-30,11,10,"493e34")
	block(-3,-28,10,8,"dfb183")
	block(-2,-27,8,5,"f0c899")
	block(4,-26,2,2,"473d32")
	block(-5,-31,11,4,"373d32")
	block(-6,-29,4,6,"434438")
	block(-5,-32,7,2,"696149")
	block(-4,-34,5,3,"4f4c3c")
	if straw:
		block(-10,-29,21,3,"8d6a3d")
		block(-8,-31,18,3,"ccb16d")
		block(-5,-33,12,3,"e6ca82")
		block(-1,-35,5,3,"ecda99")
	if is_hero:
		block(-5,-30,9,2,"67877e")
		block(-5,-12,11,2,"ac7756")
		block(-8,-12,5,6,"ad8350")
		block(-7,-12,4,2,"dbc38c")
	draw_set_transform(Vector2.ZERO)

func plant(i: int) -> void:
	var p:=bed(i)
	var cell:Dictionary=farm.s.plots[i]
	var damp:bool=cell.wet or farm.weather(farm.s.day)=="细雨"
	var soil:="#68594b" if damp else "#ab8564"
	var ridge:="#84705a" if damp else "#c19670"
	var shadow:="#584e43" if damp else "#896c51"
	for row in 4:
		var inset:=2 if row==0 or row==3 else 0
		var edge:=int((row+i)%3)
		block(p.x-28+inset+edge,p.y-8+row*5,55-2*inset,5,shadow)
		block(p.x-29+inset+edge,p.y-9+row*5,56-2*inset,5,soil)
		for speck in 8:
			var off: int=(speck*17+row*5+i*7)%49
			var high:int=(speck*7+row)%4
			block(p.x-24+off,p.y-8+row*5+high,2+(speck%3),1,ridge if speck%3 else shadow)
	for j in 4:
		var x:=p.x-19+(j%2)*30+floori(j/2.0)*4
		var y:=p.y-4+floori(j/2.0)*10
		if cell.item=="": continue
		var h:=5+mini(3,int(cell.age))*4
		block(x,y-h,2,h,"425737")
		block(x-4,y-h+1,5,3,"537956")
		block(x+1,y-h-2,6,3,"81a470")
		block(x+3,y-h-3,3,2,"acb765")
		if cell.age>=farm.GROWTH[cell.item]:
			block(x-6,y-h-2,5,4,"799858")
			block(x-4,y-h-3,4,2,"aec780")
			block(x+1,y-h+3,7,3,"557f42")
			if cell.item=="bean":
				block(x-4,y-h+2,3,6,"a7ae65")
				block(x-3,y-h+3,1,4,"e0d08a")
				block(x+3,y-h,3,5,"d5c37a")
				block(x+3,y-h+4,2,2,"a8a361")
				block(x-1,y-h-4,2,3,"e9dbaa")
			elif cell.item=="turnip":
				block(x-3,y-3,7,4,"ddd0b6")
				block(x-1,y+1,3,2,"baae93")
			else:
				block(x-5,y-h,8,5,"79a776" if cell.item=="taro" else "83afa0")
				block(x+1,y-4,5,3,"957060" if cell.item=="taro" else "ae7b62")

func boat() -> void:
	var y:=424+roundf(sin(anim*1.6))
	var x:=825.0
	if farm.s.ferry and farm.s.day%2==0: x+=sin(anim*0.22)*14
	draw_line(Vector2(x-27,y+9),Vector2(x+29,y+9),Color("#396b6566"),2)
	draw_colored_polygon(PackedVector2Array([Vector2(x-39,y-2),Vector2(x-29,y+7),Vector2(x+26,y+7),Vector2(x+42,y-5),Vector2(x+24,y),Vector2(x-24,y)]),Color("#644d35"))
	draw_line(Vector2(x-30,y+3),Vector2(x+27,y+3),Color("#a3835a"),2)
	draw_line(Vector2(x+27,y+3),Vector2(x+39,y-4),Color("#b19770"),2)
	for i in range(0,3+int(farm.s.boat)):
		block(x-27+i*5,y-2,4,4,"b48a55")
	if farm.s.boat>=8:
		block(x-12,y-15,2,15,"654d36")
		block(x+14,y-15,2,15,"654d36")
		block(x-14,y-17,31,4,"cfb27d")
		block(x+18,y-10,3,3,"efc462")

func chest(p:Vector2) -> void:
	block(p.x-14,p.y-16,30,18,"675a48")
	block(p.x-13,p.y-16,28,5,"c7ac7c")
	block(p.x-12,p.y-10,26,10,"9e805d")
	block(p.x-8,p.y-16,3,16,"786e56")
	block(p.x+9,p.y-16,3,16,"786e56")
	block(p.x,p.y-10,4,4,"e5c979")

func survey(site:int) -> void:
	var p:=site_position(site)
	var hover:=Rect2(p-Vector2(32,18),Vector2(64,36)).has_point(get_local_mouse_position())
	var ink:=Color("#36594ede") if hover else Color("#466c60b8")
	draw_rect(Rect2(p-Vector2(29,12),Vector2(58,24)),Color("#c9e3c159") if hover else Color("#c5dabe28"))
	for dx in [-1,1]:
		for dy in [-1,1]:
			var corner:=p+Vector2(dx*29,dy*12)
			draw_line(corner,corner-Vector2(dx*8,0),ink,2)
			draw_line(corner,corner-Vector2(0,dy*5),ink,2)
	if hover:
		if placing=="chest": chest(p)
		else: draw_line(p-Vector2(12,0),p+Vector2(12,0),ink,3)

func signpost(id:String) -> void:
	var point:Vector2=LOCATIONS[farm.s.zone][id]
	var side:=1 if id=="east" else -1
	var c:=point-Vector2(0,18)
	block(c.x-2,c.y,4,19,"79694b")
	draw_colored_polygon(PackedVector2Array([c+Vector2(-28*side,-8),c+Vector2(18*side,-8),c+Vector2(28*side,0),c+Vector2(18*side,8),c+Vector2(-28*side,8)]),Color("#635c45"))
	draw_string(font,c+Vector2(-21,-1+5),caption(id),HORIZONTAL_ALIGNMENT_CENTER,41,11,Color("#fff0c9"))

func draw_marsh() -> void:
	var ring:=fmod(anim*0.6,1)
	draw_set_transform(LOCATIONS.marsh.angler+Vector2(27,34),0,Vector2(1,0.35))
	draw_arc(Vector2.ZERO,3+14*ring,0,TAU,16,Color(0.82,0.93,0.85,0.65*(1-ring)),1.5)
	draw_set_transform(Vector2.ZERO)
	for id in ["greens_a","greens_b"]:
		if id in farm.s.foraged: continue
		var p:Vector2=LOCATIONS.marsh[id]
		for i in 7:
			var sprig:=p+Vector2((i*11)%29-14,(i*7)%9-4)
			block(sprig.x,sprig.y-7,2,7,"567651")
			block(sprig.x-3,sprig.y-6,4,3,"97b675")
			block(sprig.x+1,sprig.y-9,3,3,"c2c892")
	if casting:
		var bob:=Vector2(hero.x+28,hero.y+36+sin(anim*4.0)*2)
		draw_line(hero+Vector2(8,-15),hero+Vector2(26,-35),Color("#a58e63"),2)
		draw_line(hero+Vector2(26,-35),bob,Color("#e9e3ccaa"),1)
		draw_circle(bob,3,Color("#bb5d4e"))
		if bite:
			draw_arc(bob,7+fmod(anim*12,8),0,TAU,18,Color("#f5edc6"),1)

func market_stall() -> void:
	block(210,268,81,16,"84694c")
	for x in [212,284]:
		block(x,236,4,51,"66573e")
	block(206,232,89,6,"9c6154")
	for x in range(206,295,12):
		block(x,237,10,5,"ba8470")
	for x in [217,238,259]:
		block(x,264,19,8,"ba9266")
		for j in 5: block(x+2+j*3,262+j%2,3,4,"a3aa69")
	block(311,271,3,11,"786648")
	block(336,271,3,11,"786648")
	block(308,245,34,28,"655944")
	block(311,248,28,22,"ba9c71")
	block(317,250,14,16,"eee2bd")
	block(320,254,8,1,"807b61")
	block(320,257,7,1,"807b61")

func _draw() -> void:
	if farm==null: return
	if farm.s.zone=="market" and farm.s.sold_veg>=8:
		for x in [483,497,512]:
			block(x,191,13,9,"855f40")
			block(x+1,190,11,3,"adc16c")
	if farm.s.zone=="farm":
		for site in farm.BRUSH:
			if farm.has_brush(site):
				var p:=site_position(site)
				for j in 5:
					var pos:=p+Vector2(j*5-12,(j*3)%5)
					draw_line(pos,pos+Vector2(6,-5-j%3),Color("#866f4b"),2)
					block(pos.x+4,pos.y-6,5,2,"91a168")
		for i in farm.s.plots.size(): plant(i)
		if placing!="" or farm.s.tool=="hoe":
			for site in farm.YARD_SITES:
				if farm.free_site(site): survey(site)
	elif farm.s.zone=="market": boat()
	elif farm.s.zone=="marsh": draw_marsh()
	for exit_id in ["west","east"]:
		if LOCATIONS[farm.s.zone].has(exit_id): signpost(exit_id)
	var actors:Array=[{"id":"hero","p":hero}]
	for id in positions: actors.append({"id":id,"p":positions[id]})
	if farm.s.zone=="farm":
		actors.append({"id":"chest","p":LOCATIONS.farm.box})
		for site in farm.s.chests: actors.append({"id":"chest","p":site_position(site)})
	if farm.s.zone=="market": actors.append({"id":"stall","p":LOCATIONS.market.board})
	actors.sort_custom(func(a,b): return a.p.y<b.p.y)
	for a in actors:
		match a.id:
			"chest": chest(a.p)
			"stall": market_stall()
			_: person(a.p,Color("#507c77") if a.id=="hero" else BARNS[a.id],a.id=="hero",a.id=="fisher")
	if swing>0:
		var tip:=hero+Vector2(heading*(11+sin(swing*10)*6),-swing*65)
		if swing_tool=="can":
			draw_rect(Rect2(tip,Vector2(8,6)),Color("#748e91"))
			for i in 4: draw_line(tip+Vector2(i*3,6),tip+Vector2(i*3+1,10),Color("#abd9d7"),1)
		else:
			draw_line(hero+Vector2(heading*5,-12),tip,Color("#a08960"),2)
			draw_circle(tip,2,Color("#b8ac85"))
	if farm.season()==2: draw_rect(Rect2(0,0,960,540),Color("#e5a15021"))
	if farm.season()==3: draw_rect(Rect2(0,0,960,540),Color("#ccdae333"))
	if walking and target!="": draw_arc(dest,7,0,TAU,12,Color("#fbefad"),1)
	if farm.s.minutes>960:
		var dusk:=clampf((float(farm.s.minutes)-960)/300,0,1)
		draw_rect(Rect2(0,0,960,540),Color(0.14,0.19,0.31,dusk*0.53))
		var lamps:Dictionary={"farm":[Vector2(228,177)],"market":[Vector2(550,163),Vector2(851,162)],"house":[Vector2(696,172)],"marsh":[]}
		for light:Vector2 in lamps[farm.s.zone]:
			draw_circle(light,12,Color(0.97,0.72,0.33,dusk*0.13))
			draw_circle(light,6,Color(0.99,0.79,0.44,dusk*0.26))
	if farm.weather(farm.s.day)=="细雨" and farm.s.zone!="house":
		draw_rect(Rect2(0,0,960,540),Color("#7f9d9c33"))
		for i in 18:
			var ripple:=fmod(anim*0.7+i*0.39,1.0)
			var water:=Vector2(16+(i*137)%920,433+(i*23)%100)
			draw_set_transform(water,0,Vector2(1,0.28))
			draw_arc(Vector2.ZERO,2.0+8.0*ripple,0,TAU,16,Color(0.81,0.91,0.85,0.55*(1.0-ripple)),1)
		draw_set_transform(Vector2.ZERO)
		for i in 55:
			var p:=Vector2(fmod(i*113+anim*35,960),fmod(i*79+anim*145,540))
			draw_line(p,p+Vector2(-2,5),Color("#dceceb80"),1)
