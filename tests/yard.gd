extends SceneTree

const Town=preload("res://scripts/town.gd")
const Farm=preload("res://scripts/farm.gd")
var game
var errors:=0
var tmp:String

func _initialize() -> void:
	call_deferred("run")

func expect(ok:bool,why:String) -> void:
	if ok: print("PASS ",why)
	else:
		errors+=1
		printerr("FAIL ",why)

func walk_to(p:Vector2) -> void:
	var click:=InputEventMouseButton.new()
	click.position=root.get_final_transform()*p
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	root.push_input(click)
	for frame in 420:
		await process_frame
		if game.map.target=="": break

func choose(kind:String) -> void:
	game.build_button.pressed.emit()
	for button in game.content.find_children("*","Button",true,false):
		if button.text.begins_with(Farm.BUILD[kind].name):
			button.pressed.emit()
			return
	expect(false,"missing construction choice")

func run() -> void:
	tmp="user://qa-yard-%s.json" % Time.get_ticks_usec()
	var farm=Farm.new()
	var legacy:Dictionary=farm.s.duplicate(true)
	legacy.version=1
	legacy.erase("chests")
	for plot in legacy.plots: plot.erase("site")
	legacy.plots[3]={"item":"turnip","age":1,"wet":true}
	var f:=FileAccess.open(tmp,FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy))
	f.close()
	game=Town.new()
	game.save_path=tmp
	root.add_child(game)
	await process_frame
	await process_frame
	farm=game.farm
	expect(game.loaded and farm.s.version==2 and farm.s.plots[3].item=="turnip" and farm.s.plots[3].wet,"old save keeps crop, age and moisture")
	expect(game.map.bed(0)==Vector2(191,286) and game.map.bed(5)==Vector2(331,326),"original plot coordinates")
	var bad=Farm.new()
	bad.s.minutes=1190
	bad.build("field",4)
	expect(bad.s.plots.size()==6,"insufficient daylight has no effect")
	choose("chest")
	await walk_to(game.map.site_position(5))
	expect(farm.s.chests.is_empty(),"wood required before building")
	game.construction()
	choose("field")
	await walk_to(game.map.site_position(4))
	expect(farm.s.plots.size()==7 and farm.s.plots[6].site==4,"place a field by clicking the selected grass")
	var spent:int=farm.s.minutes
	farm.build("field",4)
	farm.build("field",12)
	expect(farm.s.plots.size()==7 and farm.s.minutes==spent,"occupied and non-buildable parcels reject duplicates")
	game.interact("wood")
	choose("chest")
	await walk_to(game.map.site_position(5))
	expect(farm.s.chests==[5] and farm.s.bag.wood==0,"placed chest consumes two wood once")
	game.equip("seed")
	await walk_to(game.map.bed(6))
	game.equip("can")
	await walk_to(game.map.bed(6))
	expect(farm.s.plots[6].wet and farm.s.seeds.bean==2,"expanded plot can be planted and watered")
	game.sleep_night()
	game.equip("hand")
	await walk_to(game.map.bed(6))
	game.equip("can")
	await walk_to(game.map.bed(6))
	game.sleep_night()
	game.equip("hand")
	await walk_to(game.map.bed(6))
	expect(farm.s.bag.bean==3 and farm.s.plots[6].item=="","expanded plot grows overnight and harvests")
	await walk_to(game.map.site_position(5)-Vector2(0,8))
	expect(game.page=="box","new chest opens from map")
	if game.page=="box":
		for b in game.content.find_children("*","Button",true,false):
			if b.text=="将背篓货物装箱": b.pressed.emit(); break
	game.close_sheet()
	expect(farm.s.box.bean==3 and farm.dispatch_plan().coins==9,"new shipping chest shares nightly dispatch")
	var restored=Farm.new()
	expect(restored.restore(tmp) and restored.s.plots.size()==7 and restored.s.chests==[5],"new facility positions survive reload")
	if "--capture" in OS.get_cmdline_user_args():
		game.toast.hide()
		game.map.hero=Vector2(500,325)
		game.map.dest=game.map.hero
		await process_frame
		await RenderingServer.frame_post_draw
		var frame:=root.get_texture().get_image()
		print("Captured native framebuffer: ",frame.get_size())
		frame.save_png(OS.get_environment("TEMP").path_join("liucha-yard.png"))
	game.sfx.stop()
	game.sfx.stream=null
	await create_timer(0.4).timeout
	for end in ["",".bak",".tmp"]:
		if FileAccess.file_exists(tmp+end): DirAccess.remove_absolute(tmp+end)
	quit(1 if errors else 0)
