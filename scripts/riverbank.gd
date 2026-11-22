extends Node2D

signal arrived(key: String)
const BG = preload("res://assets/village.png")
const SPOTS = {"home":Vector2(235,210),"box":Vector2(325,220),"shop":Vector2(535,205),"wood":Vector2(875,213),"dock":Vector2(778,379)}
const NAMES = {"home":"回屋歇息","box":"出货箱","shop":"阿禾的小铺","wood":"拾木料","dock":"旧渡口","carpenter":"陆木匠","fisher":"周叔"}
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

func site_position(site:int) -> Vector2:
	return Vector2(121+(site%farm.YARD_COLS)*70,286+floori(float(site)/farm.YARD_COLS)*40)

func bed(i: int) -> Vector2:
	return site_position(farm.s.plots[i].site)

func set_placement(kind:String) -> void:
	placing=kind
	target=""
	closest=""
	dest=hero
	update_spots()

func update_spots() -> void:
	spots.clear()
	if placing!="":
		for site in farm.YARD_SITES:
			if farm.free_site(site): spots["site"+str(site)]=site_position(site)
		return
	spots=SPOTS.duplicate()
	spots.merge(positions,true)
	for i in farm.s.plots.size(): spots["plot"+str(i)]=bed(i)
	for site in farm.s.chests: spots["chest"+str(site)]=site_position(site)

func _ready() -> void:
	font=ThemeDB.fallback_font
	var backdrop:=Sprite2D.new()
	backdrop.texture=BG
	backdrop.centered=false
	backdrop.scale=Vector2(960,540)/Vector2(BG.get_size())
	backdrop.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	backdrop.show_behind_parent=true
	add_child(backdrop)
	set_process(true)

func area(p: Vector2) -> Vector2:
	var ymin := 201.0
	if p.x>674 and p.x<755: ymin=223
	return Vector2(clampf(p.x,45,913),clampf(p.y,ymin,379))

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
	for id in BARNS:
		if not positions.has(id): positions[id]=npc_dest(id)
		if not paused: positions[id]=positions[id].move_toward(npc_dest(id),dt*20)
	update_spots()
	walking=false
	if not paused:
		clock+=dt
		if clock>2:
			clock=0
			farm.later(1)
		var dir:=Vector2(Input.get_axis("ui_left","ui_right"),Input.get_axis("ui_up","ui_down"))
		dir+=Vector2(int(Input.is_physical_key_pressed(KEY_D))-int(Input.is_physical_key_pressed(KEY_A)),int(Input.is_physical_key_pressed(KEY_S))-int(Input.is_physical_key_pressed(KEY_W)))
		var last:=hero
		if dir.length_squared()>0:
			target=""
			hero=area(hero+dir.normalized()*dt*128)
			dest=hero
		else:
			if spots.has(target): dest=area(spots[target]+Vector2(0,10))
			hero=hero.move_toward(dest,dt*145)
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
		if Rect2(142,106,126,94).has_point(at): pick="home"
		elif Rect2(460,92,153,100).has_point(at): pick="shop"
		elif Rect2(725,382,116,66).has_point(at): pick="dock"
	target=pick
	dest=area(at) if pick.is_empty() else area(spots[pick]+Vector2(0,10))

func caption(id: String) -> String:
	if id.begins_with("site") and placing!="": return "建"+farm.BUILD[placing].name
	if id.begins_with("chest"): return "田头出货箱"
	if id.begins_with("plot"):
		var p:Dictionary=farm.s.plots[int(id.trim_prefix("plot"))]
		if p.item=="": return "播种 · "+farm.ITEMS[farm.s.crop].name
		if p.age>=2: return "采收 · "+farm.ITEMS[p.item].name
		return "已浇水" if p.wet else "浇水"
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
		var h:=5+int(cell.age)*4
		block(x,y-h,2,h,"425737")
		block(x-4,y-h+1,5,3,"537956")
		block(x+1,y-h-2,6,3,"81a470")
		block(x+3,y-h-3,3,2,"acb765")
		if cell.age>=2:
			block(x-6,y-h-2,5,4,"799858")
			block(x-4,y-h-3,4,2,"aec780")
			block(x+1,y-h+3,7,3,"557f42")
			if cell.item=="bean":
				block(x-4,y-h+2,3,6,"a7ae65")
				block(x-3,y-h+3,1,4,"e0d08a")
				block(x+3,y-h,3,5,"d5c37a")
				block(x+3,y-h+4,2,2,"a8a361")
				block(x-1,y-h-4,2,3,"e9dbaa")
			else:
				block(x-3,y-3,7,4,"ddd0b6")
				block(x-1,y+1,3,2,"baae93")

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

func _draw() -> void:
	if farm==null: return
	if farm.s.sold_veg>=8:
		for x in [483,497,512]:
			block(x,191,13,9,"855f40")
			block(x+1,190,11,3,"adc16c")
	for i in farm.s.plots.size(): plant(i)
	for site in farm.s.chests: chest(site_position(site))
	if placing!="":
		for site in farm.YARD_SITES:
			if farm.free_site(site): survey(site)
	boat()
	chest(SPOTS.box)
	var actors:Array=[{"id":"hero","p":hero}]
	for id in positions: actors.append({"id":id,"p":positions[id]})
	actors.sort_custom(func(a,b): return a.p.y<b.p.y)
	for a in actors: person(a.p,Color("#507c77") if a.id=="hero" else BARNS[a.id],a.id=="hero",a.id=="fisher")
	if walking and target!="": draw_arc(dest,7,0,TAU,12,Color("#fbefad"),1)
	if farm.s.minutes>960: draw_rect(Rect2(0,0,960,540),Color(0.65,0.34,0.17,0.11))
	if farm.weather(farm.s.day)=="细雨":
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
