# 柳汊 · 早渡

架空江南小镇的俯视像素经营试玩版。以 Godot 4.5.1 和 GDScript 制作，使用独立 Git 仓库。

## 游玩

Windows 试玩包中双击 Liucha.exe，同目录需有 Liucha.pck。源码目录运行 Play.cmd，或以 Godot 4.5.1 打开 project.godot 后按 F6（当前场景）或 F5。启动器支持 PATH 中的 godot.exe，以及 LIUCHA_GODOT 指定的引擎。

单击地面移动，单击物件走近互动。WASD 或方向键也可以移动，E 操作最近的物件。B 打开行囊，J 打开托运簿，Esc 返回。

农舍前有三块成熟蚕豆。收下九份豆，点门外的木箱装货，到左侧农舍过夜。空地可以播种，幼苗经过两个湿润的夜晚成熟。行囊可切换种子，阿禾的小铺出售种子。留存的收成放在农舍的竹篮里。

托运簿默认每晚全卖，可拟定按物品或整类的留存和出货规则。具体物品的规则优先。工坊收木料需要木匠同意；船修好后送木约定自动结束。镇民会根据时辰移动，修船、收菜和早渡各有进度，可连续生活七天或更久。

## 模型和存档

设置中可填兼容 Chat Completions 的接口、模型 ID 和本次游玩用的密钥。默认使用本机 18760 转发的 Qwen2.5-7B，仅该默认本机接口可读取已有河湾云凭证；需要对应转发运行。其他接口可用 LIUCHA_API_KEY 或在设置中输入密钥。档案和模型地址保存在 Godot 的 user://；Windows 默认是 %APPDATA%\Liucha。游玩操作自动存档并留一份备份。日常经营、项目式托运单和默认居民日程可离线使用。

## 开发验收

在 Godot 导入资源后运行：

```
godot --headless --max-fps 60 --path . --script res://tests/play_week.gd
godot --headless --max-fps 60 --path . --script res://tests/play_week.gd -- --live
```

第二条会实际访问配置的模型。测试使用单独的临时游戏存档。Windows 导出预设为 Windows Desktop。安装 Godot 4.5.1 Windows 导出模板后可直接导出。

村景底图由 imagegen 为本项目生成，角色、作物、船、天气与音效在引擎中绘制或合成。
