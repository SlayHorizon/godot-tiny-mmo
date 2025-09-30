class_name SyncUtils


static func roughly_equal(a: Variant, b: Variant) -> bool:
	assert(typeof(a) == typeof(b), "Trying to compare different types")
	
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_VECTOR2:#TYPE_VECTOR3 etc. for 3D game
			return (a as Vector2).is_equal_approx(b)
		_:
			return a == b
