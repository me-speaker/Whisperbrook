extends SceneTree

const Town=preload("res://scripts/town.gd")
const Farm=preload("res://scripts/farm.gd")
var failures:=0
var game
var tmp:String

func _initialize() -> void:
	call_deferred("play")

func check(expr:bool, label:String) -> void:
	if not expr:
		failures+=1
		printerr("FAIL ",label)
	else: print("PASS ",label)

func play() -> void:
	tmp="user://qa-"+str(Time.get_ticks_usec())+".json"
	game=Town.new()
	game.save_path=tmp
	root.add_child(game)
	await process_frame
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("liucha-play.png"))
	var click:=InputEventMouseButton.new()
	click.position=game.map.bed(0)
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	root.push_input(click,true)
	for frame in 200:
		if game.farm.s.bag.bean>0: break
		await process_frame
	check(game.farm.s.bag.bean==3,"click the ripe plot, walk, harvest")
	game.interact("plot1")
	game.interact("plot2")
	game.interact("box")
	click_button("将背篓货物装箱")
	check(game.farm.s.box.bean==9,"load nine beans")
	game.close_sheet()
	game.book()
	game.rule_preview({"selector":"vegetable","action":"keep","count":2})
	check(game.farm.s.rules.is_empty(),"preview does not mutate the world")
	click_button("记入托运簿")
	game.close_sheet()
	game.interact("home")
	click_button("收工，睡到明早")
	check(game.farm.s.day==2 and game.farm.s.coins==27 and game.farm.s.pantry.bean==2,"9 = 7 sold + 2 kept")
	var restored=Farm.new()
	check(restored.restore(tmp) and restored.s.rules.has("vegetable") and restored.s.coins==27,"reload filed rule and household inventory")
	check(game.farm.validate({"selector":"wood","action":"workshop","count":2}).has("error"),"workshop requires resident consent")
	game.interact("carpenter")
	click_button("商量把拾来的木料送工坊")
	game.close_sheet()
	game.rule_preview({"selector":"wood","action":"workshop","count":2})
	click_button("记入托运簿")
	game.close_sheet()
	game.farm.set_rule({"selector":"bean","action":"sell","count":0})
	game.farm.s.box.bean=5
	check(game.farm.dispatch_plan().sold.bean==5,"item rule overrides category")
	game.farm.set_rule({"selector":"bean","action":"remove","count":0})
	check(game.farm.dispatch_plan().sold.bean==3,"revocation restores the category rule")
	for d in range(2,8):
		game.interact("wood")
		game.farm.deposit()
		game.interact("plot0")
		game.interact("plot0")
		game.sleep_night()
	check(game.farm.s.ferry and game.farm.s.boat==8 and not game.farm.s.rules.has("wood"),"boat finished and delivery ended; ferry runs")
	check(game.farm.s.day==8,"seven days without mandatory chat")
	if "--live" in OS.get_cmdline_user_args():
		game.book()
		await game.ask_clerk("今后每回卖货，蚕豆给我留下三份，其他照旧")
		if game.page=="rule": click_button("记入托运簿")
		var r:Dictionary=game.farm.s.rules.get("bean",{})
		check(r.get("action")=="keep" and r.get("count")==3,"real clerk draft accepted in ledger UI")
		game.npc_page("fisher")
		await game.chat("fisher","船修好了，你还打算每天开船吗？")
		var replies:Array=game.farm.s.talk.get("fisher",[])
		check(not replies.is_empty(),"real model responds in fisher conversation UI")
		if not replies.is_empty(): print("MODEL ",replies.back().reply)
	game.sfx.stop()
	game.sfx.stream=null
	await create_timer(0.35).timeout
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(tmp+suffix): DirAccess.remove_absolute(tmp+suffix)
	quit(1 if failures else 0)

func click_button(text_:String) -> void:
	for b in game.popup.find_children("*","Button",true,false):
		if b.text==text_:
			b.pressed.emit()
			return
	check(false,"missing button "+text_)
