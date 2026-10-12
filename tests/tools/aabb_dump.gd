extends SceneTree
## Prints each model's skeleton scale chain and mesh bounds (debug aid).
func _init():
	for p in ["res://assets/models/mounts/horse_bay.glb", "res://assets/models/units/NO_INF.glb"]:
		var n: Node3D = load(p).instantiate()
		root.add_child(n)
		var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
		print(p, " armature scale ", sk.get_parent().scale, " bones ", sk.get_bone_count())
		for i in mini(3, sk.get_bone_count()):
			print("  bone ", sk.get_bone_name(i), " rest ", sk.get_bone_rest(i).basis.get_scale(), " pose scale ", sk.get_bone_pose_scale(i), " origin ", sk.get_bone_rest(i).origin)
		for m in sk.get_children():
			if m is MeshInstance3D:
				print("  mesh ", m.name, " aabb ", m.get_aabb(), " skin binds ", m.skin.get_bind_count() if m.skin else 0)
				if m.skin: print("    bind0 scale ", m.skin.get_bind_pose(0).basis.get_scale())
	quit()
