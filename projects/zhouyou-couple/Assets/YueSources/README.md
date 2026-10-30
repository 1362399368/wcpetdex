# 玥默认动画素材来源

`original-pet.json` 与 `original-spritesheet.png` 来自用户提供的「WeChatPet-玥-v4.zip」。
`phone-open.png`、`phone-blink.png`、`phone-tap.png` 是以原图第 0 行角色为参考，通过 Codex 内置 imagegen 编辑模式生成的透明玩手机姿态；制作提示要求保留玥的眼镜、长发、服饰、比例和原图留白，只让她双手持手机，并另做闭眼轻眨与拇指按屏版本。
`idle-blink.png` 同样以原图第 0 行张眼站姿为参考，经 imagegen 编辑为闭眼站姿。它保持原人物的宽度和鞋底位置，避免原 v4 闭眼帧使全身突然变窄。

`build_default_pet.py` 把玩手机姿态按原人物边界缩放，在第 8 行合成 10 个站立玩手机画格；第 0 行用新闭眼帧及眼部半闭过渡替换原来的骤缩帧。其余 27 行逐像素保留。脚本只做裁剪、透明度清理、尺寸与帧位排布；绘画内容来自上述图片。运行需要 Python 3 和 Pillow：

```sh
python3 Assets/YueSources/build_default_pet.py
```

输出为 `Resources/DefaultPet/pet.json` 与 `spritesheet.png`。元数据仍是 v4 的 29 行、19 种语义动作；额外 `onlinePhoneRow: 8` 供周游个人版在线状态使用。`passiveAnimations` 让静止站立约每 4.8 秒眨眼一次，在线玩手机约每 5.2 秒眨眼一次，两者其余时间保持轻微呼吸及手机点击动作。第 1 行向右跑、第 2 行向左跑，运行时代码在拖动时按方向选择。
