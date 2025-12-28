class_name MobResource
extends NPCResource


const DEFAULT_RESPAWN_DELAY: float = 30.0
const RESPAWN_CHECK_RADIUS_MULTIPLIER: float = 2.0
const DEFAULT_RESPAWN_POSITION_VARIANCE: float = 50.0  # Default radius for respawn position variation


@export var abilities: Array[AbilityResource] = []
@export var respawn_delay: float = DEFAULT_RESPAWN_DELAY
@export var respawn_check_radius: float = 0.0  # 0 means auto-calculate from detection_radius
@export var respawn_position_variance: float = DEFAULT_RESPAWN_POSITION_VARIANCE  # Radius around original spawn position for respawn variation
@export var mana_max: float = 0.0  # 0 means no mana


func get_respawn_check_radius() -> float:
	# Auto-calculate if not set
	if respawn_check_radius == 0.0:
		return detection_radius * RESPAWN_CHECK_RADIUS_MULTIPLIER
	return respawn_check_radius
