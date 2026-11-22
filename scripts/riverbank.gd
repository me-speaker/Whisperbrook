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

func bed(i: int) -> Vector2:
	return Vector2(191+(i%3)*70,286+floori(i/3.0)*40)

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
	spots=SPOTS.duplicate()
	for id in BARNS:
		if not positions.has(id): positions[id]=npc_dest(id)
		if not paused: positions[id]=positions[id].move_toward(npc_dest(id),dt*20)
		spots[id]=positions[id]
	for i in 6: spots["plot"+str(i)]=bed(i)
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
		var offset:=Vector2.ZERO if id.begins_with("plot") else Vector2(0,-11)
		var d=at.distance_to(spots[id]+offset)
		var radius:=33 if id.begins_with("plot") else 30
		if d<radius and d<score:
			pick=id
			score=d
	if pick=="":
		if Rect2(142,106,126,94).has_point(at): pick="home"
		elif Rect2(460,92,153,100).has_point(at): pick="shop"
		elif Rect2(725,382,116,66).has_point(at): pick="dock"
	target=pick
	dest=area(at) if pick.is_empty() else area(spots[pick]+Vector2(0,10))

func caption(id: String) -> String:
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
	var soil:="#715039" if cell.wet else "#996849"
	for row in 4:
		var inset:=2 if row==0 or row==3 else 0
		block(p.x-29+inset,p.y-8+row*5,58-2*inset,5,"71563e")
		block(p.x-28+inset,p.y-9+row*5,56-2*inset,4,soil)
		for speck in 4:
			var off: int=(speck*17+row*5+i*7)%48
			block(p.x-24+off,p.y-8+row*5,3,2,"71563f" if cell.wet else "ac8057")
	for j in 4:
		var x:=p.x-19+(j%2)*30+floori(j/2.0)*4
		var y:=p.y-4+floori(j/2.0)*10
		if cell.item=="": continue
		var h:=4+int(cell.age)*4
		block(x,y-h,2,h,"425737")
		block(x-4,y-h+1,5,3,"526e3c")
		block(x+1,y-h-2,6,3,"749549")
		block(x+3,y-h-3,3,2,"acb765")
		if cell.age>=2:
			block(x-6,y-h-2,5,4,"799858")
			block(x-4,y-h-3,4,2,"aec780")
			block(x+1,y-h+3,7,3,"557f42")
			if cell.item=="bean":
				block(x-3,y-h+2,2,5,"d6aa56")
				block(x+3,y-h,2,5,"f1ce79")
			else: block(x-2,y-2,6,4,"e9d8bc")

func boat() -> void:
	var y:=424+roundf(sin(anim*1.6))
	var x:=825.0
	if farm.s.ferry and farm.s.day%2==0: x+=sin(anim*0.22)*14
	draw_colored_polygon(PackedVector2Array([Vector2(x-39,y-2),Vector2(x-29,y+7),Vector2(x+26,y+7),Vector2(x+42,y-5),Vector2(x+24,y),Vector2(x-24,y)]),Color("#644d35"))
	for i in range(0,3+int(farm.s.boat)):
		block(x-27+i*5,y-2,4,4,"b48a55")
	if farm.s.boat>=8:
		block(x-12,y-15,2,15,"654d36")
		block(x+14,y-15,2,15,"654d36")
		block(x-14,y-17,31,4,"cfb27d")
		block(x+18,y-10,3,3,"efc462")

func _draw() -> void:
	if farm==null: return
	if farm.s.sold_veg>=8:
		for x in [483,497,512]:
			block(x,191,13,9,"855f40")
			block(x+1,190,11,3,"adc16c")
	for i in 6: plant(i)
	boat()
	# Shipping chest, with high plank lid and brass latch.
	block(311,204,30,18,"554635")
	block(312,204,28,5,"c7a16b")
	block(313,210,26,10,"967249")
	block(317,204,3,16,"75674e")
	block(334,204,3,16,"75674e")
	block(325,210,4,4,"e5c979")
	var actors:Array=[{"id":"hero","p":hero}]
	for id in positions: actors.append({"id":id,"p":positions[id]})
	actors.sort_custom(func(a,b): return a.p.y<b.p.y)
	for a in actors: person(a.p,Color("#507c77") if a.id=="hero" else BARNS[a.id],a.id=="hero",a.id=="fisher")
	if walking and target!="": draw_arc(dest,7,0,TAU,12,Color("#fbefad"),1)
	if farm.s.minutes>960: draw_rect(Rect2(0,0,960,540),Color(0.65,0.34,0.17,0.11))
	if farm.weather(farm.s.day)=="细雨":
		draw_rect(Rect2(0,0,960,540),Color("#637d922b"))
		for i in 55:
			var p:=Vector2(fmod(i*113+anim*35,960),fmod(i*79+anim*145,540))
			draw_line(p,p+Vector2(-2,5),Color("#dceceb80"),1)
