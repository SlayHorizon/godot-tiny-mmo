class_name BurnDotEffect
extends GameplayEffect


@export var dps: float = 10.0
@export var duration: float = 3.0
@export var tick: float = 0.5

var source_eid: int


func on_added(asc: AbilitySystemComponent) -> void:
	# Tick périodique (serveur)
	var t := Timer.new()
	t.wait_time = tick
	t.one_shot = false
	t.autostart = true
	t.timeout.connect(func():
		var spec := EffectSpec.damage(source_eid, dps * tick, ["Damage.True", "Periodic", "Burn"])
		asc.apply_spec_server(spec, asc) # source = asc ? mieux: résous via source_eid -> ASC
		t.queue_free()
	)
	asc.add_child(t)

	# Fin de l’effet
	var end := Timer.new()
	end.wait_time = duration
	end.one_shot = true
	end.autostart = true
	end.timeout.connect(func():
		end.queue_free()
		on_removed(asc)
	)
	asc.add_child(end)
