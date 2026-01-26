#
#@onready var anim_player: AnimationPlayer = $AnimationPlayer
#@onready var anim_tree: AnimationTree = $AnimationTree
#
#const RIGHT_PREFIX := "HandOffset/HandPivot/RightHandSpot"
#const LEFT_PREFIX  := "HandOffset/HandPivot/LeftHandSpot"
#
#var _mirror_cache := {} # key: ObjectID or resource_path -> AnimationLibrary
#
#func equip_weapon(profile: WeaponAnimationProfile, hand: StringName):
	#var slot := "weapon_%s" % hand
	#if anim_player.has_animation_library(slot):
		#anim_player.remove_animation_library(slot)
#
	#var lib: AnimationLibrary = profile.library
	#if hand == &"left":
		#lib = _get_or_make_mirrored_library(profile.library)
#
	#anim_player.add_animation_library(slot, lib)
#
	#var side := (hand == &"right") ? "Right" : "Left"
	#anim_tree.set("parameters/OnFoot/%sIdle/animation"   % side, profile.idle_anim)   # e.g. "sword.idle"
	#anim_tree.set("parameters/OnFoot/%sAction/animation" % side, profile.attack_anim) # e.g. "sword.swing"
#
#func _get_or_make_mirrored_library(src: AnimationLibrary) -> AnimationLibrary:
	#var key := src.resource_path if src.resource_path != "" else str(src.get_instance_id())
	#if _mirror_cache.has(key):
		#return _mirror_cache[key]
#
	#var dst := AnimationLibrary.new()
	#for name in src.get_animation_list():
		#var anim := src.get_animation(name)
		#var mirrored := _mirror_animation(anim, RIGHT_PREFIX, LEFT_PREFIX)
		#dst.add_animation(name, mirrored) # same names on purpose
	#_mirror_cache[key] = dst
	#return dst
#
#func _mirror_animation(anim: Animation, from_prefix: String, to_prefix: String) -> Animation:
	#var out: Animation = anim.duplicate(true)
	#for i in range(out.get_track_count()):
		#var path: NodePath = out.track_get_path(i)
		#if str(path).begins_with(from_prefix):
			#var new_path := NodePath(str(path).replace(from_prefix, to_prefix))
			#out.track_set_path(i, new_path)
#
			#if out.track_get_type(i) == Animation.TYPE_VALUE:
				#var key_count := out.track_get_key_count(i)
				#var prop := str(path).get_slice(":", 1) if ":" in str(path) else ""
				#for k in range(key_count):
					#var v := out.track_get_key_value(i, k)
					#if prop == "rotation" and v is float:
						#v = -v
					#elif prop == "position" and v is Vector2:
						#v.x = -v.x
					#elif prop == "scale" and v is Vector2:
						#v.x = -v.x
					#out.track_set_key_value(i, k, v)
	#return out
