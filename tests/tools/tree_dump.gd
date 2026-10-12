extends SceneTree
func _init():
	for p in ["res://assets/models/mounts/horse_bay.glb", "res://assets/models/riders/NO_SPU.glb"]:
		var n = load(p).instantiate()
		_dump(n, 0)
		var ap = n.find_child("AnimationPlayer", true, false)
		if ap: print("  anims: ", ap.get_animation_list())
	quit()
func _dump(n, d):
	print("  ".repeat(d), n.name, " [", n.get_class(), "] scale=", n.scale if n is Node3D else "", (" bone=" + n.bone_name) if n is BoneAttachment3D else "")
	for c in n.get_children(): _dump(c, d + 1)
