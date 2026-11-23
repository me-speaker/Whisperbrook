extends SceneTree

const Town=preload("res://scripts/town.gd")
const Farm=preload("res://scripts/farm.gd")
var game
var map
var errors:=0
var tmp:String

func _initialize() -> void: call_deferred("run")

func check(ok:bool,msg:String) -> void:
	if ok: print("PASS ",msg)
	else:
		errors+=1
		printerr("FAIL ",msg)

func press(code:Key) -> void:
	var ev:=InputEventKey.new()
	ev.keycode=code
	ev.physical_keycode=code
	ev.pressed=true
	root.push_input(ev)
	ev.pressed=false
	root.push_input(ev)

func click(p:Vector2,button:=MOUSE_BUTTON_LEFT) -> void:
	var ev:=InputEventMouseButton.new()
	ev.position=root.get_final_transform()*p
	ev.button_index=button
	ev.pressed=true
	root.push_input(ev)
	ev.pressed=false
	root.push_input(ev)

func settle() -> void:
	for frame in 650:
		await process_frame
		if map.target=="" and map.route.is_empty() and map.dest.distance_to(map.hero)<1: break

func place(kind:String,p:Vector2) -> void:
	game.construction()
	for b in game.content.find_children("*","Button",true,false):
		var caption:String="平整空畦" if kind=="reclaim" else Farm.BUILD[kind].name
		if b.text.begins_with(caption):
			b.pressed.emit()
			click(p)
			await settle()
			return
	check(false,"construction button "+kind)

func run() -> void:
	tmp="user://qa-free-yard-%d.json"%Time.get_ticks_usec()
	game=Town.new()
	game.save_path=tmp
	root.add_child(game)
	map=game.map
	await process_frame
	var f=game.farm
	check(f.s.plots.is_empty() and f.s.chests.is_empty() and not map.spots.has("box"),"new game leaves layout to player")
	var v2:Dictionary=f.s.duplicate(true)
	v2.version=2
	v2.erase("legacy_box")
	v2.plots=[{"site":32,"item":"bean","age":1,"wet":true}]
	v2.chests=[13]
	v2.cleared=[32]
	var old:=Farm.new()
	old.s=v2
	old.save_to(tmp+".old")
	var migrated:=Farm.new()
	check(migrated.restore(tmp+".old") and migrated.s.legacy_box and migrated.tile_center(migrated.s.plots[0].site)==Vector2(821,366) and migrated.tile_center(migrated.s.chests[0])==Vector2(191,366) and not migrated.has_brush(migrated.s.plots[0].site),"expanded v2 fields, chest and cleared brush retain world coordinates")
	migrated.reclaim(-1)
	check(not migrated.s.legacy_box,"original house chest can also be packed")
	var a:=Vector2(128,265)
	var b:=Vector2(394,381)
	map.travel("farm",a)
	click(b,MOUSE_BUTTON_RIGHT)
	var aligned:=true
	for i in 400:
		await process_frame
		if absf((b-a).normalized().cross(map.hero-a))>0.05: aligned=false
		if map.hero.distance_to(b)<0.1: break
	check(aligned and map.hero.distance_to(b)<0.1,"unobstructed arbitrary-angle click is exactly straight")
	var tile:=Vector2(890,405)
	press(KEY_2)
	click(tile)
	await settle()
	check(f.s.plots.size()==1 and f.s.plots[0].site==f.tile_at(tile),"hoe edits a grass tile outside the old site list")
	press(KEY_3)
	click(tile)
	await settle()
	await place("reclaim",tile)
	check(f.s.plots.size()==1 and f.s.plots[0].item=="bean","reclaim protects a planted crop")
	var box:=Vector2(541,406)
	await place("chest",box)
	check(f.s.chests==[f.tile_at(box)] and not map.walkable(box),"player's new chest is a navigation obstacle")
	a=box-Vector2(83,0)
	b=box+Vector2(102,0)
	map.travel("farm",a)
	var route:PackedVector2Array=map.path_to(a,b)
	var safe:=route.size()>1 and route.size()<=5
	for end in route:
		safe=safe and map.segment_clear(a,end)
		a=end
	check(safe,"obstacle detour has only visible safe straight segments")
	click(b,MOUSE_BUTTON_RIGHT)
	await settle()
	check(map.hero.distance_to(b)<0.1,"detour reaches clicked ground")
	f.s.box.bean=2
	await place("reclaim",box)
	check(f.s.chests.is_empty() and map.walkable(box) and f.s.bag.wood==2 and f.s.box.bean==2,"dismantling returns materials and keeps cargo")
	await place("chest",Vector2(51,286))
	var restored=Farm.new()
	check(restored.restore(tmp) and restored.s.plots[0].site==f.tile_at(tile) and restored.s.chests==[0],"freely chosen properties survive reload")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("liucha-free-yard.png"))
	map.travel("house",Vector2(296,254))
	await process_frame
	await process_frame
	var before:Vector2=map.hero
	press(KEY_E)
	check(game.page=="home" and before==map.hero,"E opens bed from the side outside the old center radius")
	game.close_sheet()
	map.travel("market",Vector2(254,307))
	await process_frame
	await process_frame
	before=map.hero
	click(Vector2(266,250))
	await settle()
	check(game.page=="board" and before==map.hero,"clicking reachable stall uses it without walking to an anchor")
	game.close_sheet()
	map.travel("marsh",Vector2(181,335))
	press(KEY_5)
	await process_frame
	await process_frame
	press(KEY_E)
	check(map.casting,"cast from a different stretch of riverbank using E")
	game.finish_fishing(false)
	game.sfx.stop()
	game.sfx.stream=null
	await create_timer(0.35).timeout
	for ext in ["",".tmp",".bak",".old"]:
		if FileAccess.file_exists(tmp+ext): DirAccess.remove_absolute(tmp+ext)
	quit(1 if errors else 0)
