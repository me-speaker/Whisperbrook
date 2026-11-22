extends SceneTree

const Town=preload("res://scripts/town.gd")
const Farm=preload("res://scripts/farm.gd")
var town
var errors:=0
var tmp:String

func _initialize() -> void: call_deferred("tour")

func check(ok:bool,what:String) -> void:
	if ok: print("PASS ",what)
	else:
		errors+=1
		printerr("FAIL ",what)

func press(keycode:Key) -> void:
	var key:=InputEventKey.new()
	key.physical_keycode=keycode
	key.keycode=keycode
	key.pressed=true
	root.push_input(key)
	key.pressed=false
	root.push_input(key)

func click_at(p:Vector2) -> void:
	var ev:=InputEventMouseButton.new()
	ev.position=root.get_final_transform()*p
	ev.button_index=MOUSE_BUTTON_LEFT
	ev.pressed=true
	root.push_input(ev)
	for i in 650:
		await process_frame
		if town.map.target=="": break

func use(id:String) -> void:
	await process_frame
	if not town.map.spots.has(id):
		check(false,"map spot "+id)
		return
	await click_at(town.map.spots[id]+Vector2(0,-6))

func button(name_:String) -> void:
	for b in town.content.find_children("*","Button",true,false):
		if b.text.begins_with(name_):
			b.pressed.emit()
			return
	check(false,"missing button "+name_)

func screenshot(name_:String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	town.toast.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("liucha-"+name_+".png"))

func tour() -> void:
	tmp="user://tour-%d.json" % Time.get_ticks_usec()
	town=Town.new()
	town.save_path=tmp
	root.add_child(town)
	await process_frame
	await process_frame
	var f=town.farm
	await screenshot("homestead")
	press(KEY_2)
	await use("site18")
	await use("site18")
	check(f.s.cleared.has(18) and f.s.plots.back().site==18 and f.s.bag.wood==1,"short hoe clears brush and prepares eastern field")
	press(KEY_4)
	await use("plot6")
	press(KEY_3)
	await use("plot6")
	check(f.s.plots[6].wet and f.s.plots[6].item=="bean" and f.s.water==5,"prewatered soil survives sowing")
	await use("well")
	check(f.s.water==f.capacity(),"fill can at farm well")
	press(KEY_1)
	await use("plot0")
	await use("plot1")
	await use("east")
	check(f.s.zone=="market" and not town.map.spots.has("plot0"),"farm path leads into a separate town")
	await screenshot("market")
	await use("shop")
	button("从背篓里送份心意")
	button("蚕豆")
	check(f.s.bag.bean==5 and f.s.friendship.shop==2,"gift transfers real inventory")
	town.close_sheet()
	await use("board")
	button("从背篓交货")
	check(f.s.bag.bean==2 and f.s.coins==20 and f.s.delivery_day==f.s.day,"square commission paid from backpack")
	f.deliver_request()
	check(f.s.coins==20,"completed commission cannot pay twice")
	await use("east")
	check(f.s.zone=="marsh","town path leads to reed bank")
	await use("greens_a")
	await use("greens_a")
	check(f.s.bag.herb==2,"forage once per patch per day")
	press(KEY_5)
	await use("angler")
	check(town.map.casting,"cast at water")
	for i in 800:
		await process_frame
		if town.map.bite: break
	await screenshot("water")
	press(KEY_E)
	check(f.s.bag.fish==1 and not town.map.casting,"on-time reel lands a fish")
	await use("west")
	await use("west")
	await use("home")
	check(f.s.zone=="house","walk into farmhouse")
	await screenshot("interior")
	# Keep this fish for the clerk's trial instead of eating it.
	await use("outside")
	await use("box")
	button("将背篓货物装箱")
	town.close_sheet()
	town.book()
	if "--live" in OS.get_cmdline_user_args():
		await town.ask_clerk("今后每天卖货时，河鲫请留一尾在家，其余照旧。")
	else: town.rule_preview({"selector":"fish","action":"keep","count":1})
	check(town.page=="rule","fish retention has a reviewable clerk draft")
	if town.page=="rule": button("记入托运簿")
	town.close_sheet()
	await use("home")
	await use("bed")
	button("收工，睡到明早")
	check(f.s.pantry.fish==1 and f.s.bag.fish==0 and f.s.energy==f.MAX_ENERGY and f.s.zone=="farm","sleep restores energy and honors shipping rule")
	var save=Farm.new()
	check(save.restore(tmp) and save.s.pantry.fish==1 and save.s.cleared.has(18),"new world and classic farm state persist together")
	f.s.bag.herb=1
	f.s.energy=4
	await use("home")
	await use("stove")
	button("起火煮汤")
	check(f.s.energy==26 and f.s.pantry.fish==0 and f.s.bag.herb==0,"stove uses pantry and backpack")
	for i in 14:
		f.night()
		if f.early_market(): break
	await use("outside")
	await use("east")
	await use("dock")
	button("搭早渡到芦湾钓台")
	check(f.s.zone=="marsh","repaired ferry opens playable shortcut")
	await use("west")
	f.s.bag.fish=2
	var coins:int=f.s.coins
	await use("shop")
	button("早渡鱼市")
	check(f.s.bag.fish==0 and f.s.coins==coins+16,"morning market pays immediately exactly once")
	town.close_sheet()
	f.s.day=14
	f.night()
	check(f.season()==1 and f.season_day()==1 and f.buy_seed("bean").contains("本季") and f.buy_seed("lotus").contains("买下"),"summer stock follows calendar")
	f.s.minutes=1320
	await process_frame
	await process_frame
	check(f.s.zone=="farm" and f.s.minutes==420,"nightfall brings player home")
	town.sfx.stop()
	town.sfx.stream=null
	await create_timer(0.4).timeout
	for ext in ["",".bak",".tmp"]:
		if FileAccess.file_exists(tmp+ext): DirAccess.remove_absolute(tmp+ext)
	quit(1 if errors else 0)
