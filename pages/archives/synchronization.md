## Synchronization States

The project’s networking code is designed to be flexible, and how you synchronize entities is entirely up to you.  
One approach I have used is to leverage the [Entity Class](https://github.com/SlayHorizon/godot-tiny-mmo/blob/main/source/common/entities/entity.gd).  
This class, defined in `common/entity`, is used by both the client and the game server.

This class has two key properties that help with synchronization (similar to the `MultiplayerSynchronizer`):
```gdscript
var spawn_state: Dictionary = {}:
    set = _set_spawn_state
var sync_state: Dictionary = {}:
    set = _set_sync_state
```
- `spawn_state` is used for initial state setup, such as setting a character’s texture, stats, name, etc., when they first spawn in the game.
- `sync_state` is updated frequently, usually every frame, to reflect real-time updates like position, rotation, animation, etc.

If you want to add custom synchronization logic, you can override the setters in child classes, like the [Character class](https://github.com/SlayHorizon/godot-tiny-mmo/blob/main/source/common/entities/characters/character.gd):
```gdscript
func _set_sync_state(new_state: Dictionary) -> void:
    sync_state = new_state
    for property: String in new_state:
        set(property, new_state[property])


func _set_spawn_state(new_state: Dictionary) -> void:
    spawn_state = new_state
    if not is_node_ready():
        await ready
    for property: String in new_state:
        set(property, new_state[property])
```

---

## Synchronization Process

Now, how is this used to actually synchronize all the entities?

### Server-Side

Here's how it can be implemented on the game server side, in `world_server/../instance_server.gd`:

```gdscript
func _physics_process(_delta: float) -> void:
    # EC stands for EntityCollection. We aim to minimize key names in the dictionary for speed.
    var state: Dictionary = {"EC" = {}}

    # Get all sync_state properties of all entities in the current instance and add them to the dictionary.
    for entity_id: int in entity_collection:
        state["EC"][entity_id] = (entity_collection[entity_id] as Entity).sync_state

    state["T"] = Time.get_unix_time_from_system()

    # Fetch the dictionary for all entities in the instance.
    for peer_id: int in connected_peers:
        fetch_instance_state.rpc_id(peer_id, state)
```

Some of you may think this is a bad approach, but here, I want to focus on simplicity and scalability. This code is easy to understand and adaptable, meaning it can be optimized later.

### Two areas you could optimize here:
- Use a more optimized representation, like bit-packing, instead of a plain dictionary.
- If your game allows for a large number of entities in a single instance or if your instances are large, consider only sending the state of entities near the player.

### Client-Side

On the client side, you simply receive the RPC call, as shown below in `client/../instance_client.gd`:

```gdscript
@rpc("authority", "call_remote", "reliable", 0)
func fetch_instance_state(new_state: Dictionary):
    if new_state["T"] > last_state["T"]:
        last_state = new_state
        update_entity_collection(new_state["EC"]) # EC = EntityCollection


func update_entity_collection(collection_state: Dictionary) -> void:
    # Ignore its own state.
    collection_state.erase(multiplayer.get_unique_id())

    # Iterate over the dictionary and update each entity's sync state.
    for entity_id: int in collection_state:
        if entity_collection.has(entity_id):
            (entity_collection[entity_id] as Entity).sync_state = collection_state[entity_id]
```

---

### Client-Side (Player)

Now, for the client’s player, we simply define the `sync_state` like this in `local_player.gd`:

```gdscript
class_name LocalPlayer
extends Player

signal sync_state_defined(sync_state: Dictionary)
...

func _physics_process(delta: float) -> void:
    # Other functions
    define_sync_state()
...

func define_sync_state() -> void:
    sync_state = {
        "T": Time.get_unix_time_from_system(),
        "position": get_global_position(),
        "flipped": flipped,
        "anim": anim,
        "pivot": snappedf(hand_pivot.rotation, 0.05)
    }
...

func _set_sync_state(new_state: Dictionary) -> void:
    # Code to check if there is anything to update.
    # If so, emit the signal that will trigger `fetch_player_state(sync_state)`
    # with only the new changes.
    if update_state.size() > 1:
        sync_state_defined.emit(update_state)
```
As written in the comments, the correct signal will call the RPC function `fetch_player_state(sync_state)`,  
which you can find in both `instance_server.gd` and `instance_client.gd`.

---

### Additional Notes

One thing to keep in mind: a malicious player could potentially modify this code and send arbitrary data, and there is almost no way to fully prevent this without an intrusive anti-cheat system. However, we can still double-check and block this kind of behavior on the server side later!
