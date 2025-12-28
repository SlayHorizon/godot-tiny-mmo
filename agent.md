# Agent Guide: Godot Tiny MMO

This document provides essential information for AI agents working on the **Godot Tiny MMO** project - an experimental open-source MMORPG framework built with Godot 4.

## Project Overview

**Godot Tiny MMO** is a cross-platform MMORPG framework that demonstrates scalable multiplayer architecture using:
- **Custom netcode** with efficient byte-packed networking (PackedByteArray instead of string-based messages)
- **True MMOO architecture** with Gateway, Master, and World servers
- **Unified codebase** - client and multiple servers in one repository
- **Cross-platform** support: browser, desktop, and mobile

### Key Features
- Client-Server connection through `WebSocketMultiplayerPeer`
- Authentication system with account creation and guest login
- Character creation with RPG class system (Knight, Rogue, Wizard)
- Basic combat system with weapons
- Entity synchronization with interpolation
- Instance-based maps with traveling between different map instances
- Server-side NPCs with AI logic
- Instance-based chat for localized communication

## Project Structure

```
godot-tiny-mmo/
├── addons/                    # Custom plugins
│   ├── httpserver/           # HTTP server addon
│   └── tinymmo/              # Tiny MMO editor plugin
├── assets/                   # Game assets (sprites, fonts, audio, etc.)
├── data/                     # Configuration files
│   └── config/               # Server/client configs
├── source/                   # Main source code
│   ├── client/               # Client-side code
│   │   ├── autoload/        # ClientState autoload
│   │   ├── gateway/         # Gateway connection UI
│   │   ├── local_player/    # Local player controller
│   │   ├── network/         # Client networking
│   │   └── ui/              # User interface
│   ├── common/              # Shared code (client & server)
│   │   ├── gameplay/        # Gameplay systems
│   │   │   ├── characters/  # Character classes
│   │   │   ├── combat/      # Combat system
│   │   │   ├── items/       # Item system
│   │   │   └── maps/        # Map and instance resources
│   │   ├── network/         # Network protocol & sync
│   │   ├── registry/        # PathRegistry for property sync
│   │   └── utils/           # Shared utilities
│   └── server/              # Server-side code
│       ├── gateway/         # Gateway server (auth & routing)
│       ├── master/          # Master server (orchestration)
│       └── world/           # World server (gameplay)
└── project.godot            # Godot project configuration
```

## Architecture

### Server Architecture (MMOO Pattern)

The project uses a **three-tier server architecture**:

1. **Gateway Server** (`source/server/gateway/`)
   - Handles authentication and routing
   - Connects players to appropriate world servers
   - Communicates with master server for server lists
   - Entry point for all client connections

2. **Master Server** (`source/server/master/`)
   - Orchestrator for the entire system
   - Manages account data and authentication
   - Bridges communication between gateways and world servers
   - Provides server lists to gateways
   - Generates temporary tokens for world server access

3. **World Server** (`source/server/world/`)
   - Hosts multiple concurrent maps and instances
   - Where actual gameplay happens
   - Manages player instances, NPCs, combat, chat
   - Handles instance management and map transitions

### Client Architecture

The client (`source/client/`) handles:
- Connection to gateway server
- UI for login, server selection, character creation
- Local player control and rendering
- Network synchronization of remote entities
- Game state management via `ClientState` autoload

## Networking Protocol

### Custom Byte-Packed Protocol

The project uses a **custom binary protocol** instead of Godot's built-in `MultiplayerSynchronizer/Spawner`:

- **Wire Codec** (`source/common/network/wire_codec.gd`): Encodes/decodes binary data
- **Wire Types** (`source/common/network/wire.gd`): Defines data types (U8, U16, F32, VEC2_F32, etc.)
- **PackedByteArray**: Efficient binary serialization using `StreamPeerBuffer`

### Key Networking Components

1. **BaseMultiplayerEndpoint** (`source/common/network/endpoints/base_multiplayer_endpoint.gd`)
   - Base class for client/server networking
   - Uses `WebSocketMultiplayerPeer` for connections
   - Handles TLS options for secure connections

2. **WireCodec** (`source/common/network/wire_codec.gd`)
   - Encodes deltas (property changes)
   - Encodes bootstrap data (initial state)
   - Encodes container blocks (spawns/despawns)

3. **State Synchronization** (`source/common/network/sync/`)
   - `StateSynchronizer`: Manages property replication
   - `PropertyCache`: Tracks property changes
   - `ReplicatedProps`: Defines which properties sync

4. **PathRegistry** (`source/common/registry/path_registry.gd`)
   - Maps property paths to field IDs
   - Enables efficient property synchronization
   - Supports dynamic schema updates via bootstrap

### Message Types

- **Delta messages**: Incremental property updates
- **Bootstrap messages**: Initial state with schema updates
- **Container messages**: Entity spawns/despawns and method calls

## Running the Project

### Setup

1. Open project in **Godot 4.4 or 4.5**
2. Go to **Debug** tab → **"Customizable Run Instance..."**
3. Enable **Multiple Instances** (set to 4 or more)
4. Configure **Feature Tags**:
   - Exactly **one** "gateway-server" tag
   - Exactly **one** "master-server" tag
   - Exactly **one** "world-server" tag
   - At least **one or more** "client" tags
5. (Optional) Add launch arguments:
   - `--headless` for servers (prevents empty windows)
   - `--config=config_file_path.cfg` for custom config
6. Press **F5** to run

### Entry Point

The main entry point is `source/common/main.gd`, which:
- Checks feature tags or command-line arguments
- Routes to appropriate scene based on role:
  - `client` → `source/client/client_main.tscn`
  - `gateway-server` → `source/server/gateway/gateway_main.tscn`
  - `master-server` → `source/server/master/master_main.tscn`
  - `world-server` → `source/server/world/world_main.tscn`

## Key Systems

### Instance Management

**InstanceManagerServer** (`source/server/world/components/instance_manager.gd`):
- Manages multiple map instances
- Handles player transitions between instances
- Unloads unused instances automatically
- Supports instance collections (overworld, dungeon, etc.)

### Entity System

- **Entity** (`source/common/gameplay/characters/entity.gd`): Base class for all networked entities
- **Player** (`source/common/gameplay/characters/player/player.gd`): Player character
- **NPC** (`source/common/gameplay/characters/npc/npc.gd`): Server-controlled NPCs
- **Character** (`source/common/gameplay/characters/character.gd`): Base character with stats/combat

### Combat System

- **Ability System** (`source/common/gameplay/combat/ability/`): Abilities and cooldowns
- **Attack System** (`source/common/gameplay/combat/attack/`): Attack resolution
- **Attributes** (`source/common/gameplay/combat/attributes/`): Stats and modifiers
- **Equipment** (`source/common/gameplay/combat/components/equipment_component.gd`): Item equipping

### Item System

- **Item** (`source/common/gameplay/items/item.gd`): Base item class
- **WeaponItem** (`source/common/gameplay/items/weapon_item.gd`): Weapons
- **GearItem** (`source/common/gameplay/items/gear_item.gd`): Equipment
- **Item Slots** (`source/common/gameplay/items/item_slot/`): Equipment slots

### Maps & Instances

- **Map** (`source/common/gameplay/maps/map.gd`): Base map class
- **InstanceResource** (`source/common/gameplay/maps/instance/instance_resource.gd`): Instance configuration
- **Teleporter/Warper** (`source/common/gameplay/maps/components/interaction_areas/`): Map transitions

## Code Conventions

### Naming Conventions

- **Files**: Use `snake_case` (e.g., `player_character.gd`, `main_menu.tscn`)
- **Classes**: Use `PascalCase` with `class_name` (e.g., `PlayerCharacter`)
- **Variables**: Use `snake_case` (e.g., `health_points`, `current_instance`)
- **Constants**: Use `ALL_CAPS_SNAKE_CASE` (e.g., `MAX_HEALTH`)
- **Functions**: Use `snake_case` (e.g., `move_player()`, `calculate_damage()`)
- **Nodes**: Use `PascalCase` in scene tree (e.g., `PlayerCharacter`, `MainCamera`)
- **Signals**: Use `snake_case` in past tense (e.g., `health_depleted`, `enemy_defeated`)

### GDScript Best Practices

- Use strict typing for all variables and function parameters
- Document complex functions with docstrings
- Keep methods focused and under 30 lines when possible
- Use `@onready` annotations instead of direct node references in `_ready()`
- Prefer composition over inheritance where possible
- Use signals for loose coupling between nodes
- Implement `_ready()` and lifecycle functions with explicit `super()` calls

### Network Code Guidelines

- Always validate input on the server
- Use server-authoritative game logic
- Send only necessary data (deltas, not full state)
- Handle network errors gracefully
- Implement proper cleanup in `_exit_tree()`
- Use `PackedByteArray` for efficient network messages

## Configuration Files

Configuration files are located in `data/config/`:
- `client_config.cfg`: Client settings
- `gateway_config.cfg`: Gateway server config
- `master_config.cfg`: Master server config
- `world_config.cfg`: World server config

Configs can be specified via `--config=path/to/config.cfg` launch argument.

## Database

The project uses **QAD Database** for persistent data storage:
- Account data stored on master server
- Character data stored on world servers
- Supports guest accounts for quick access

## Testing & Development

### Multiple Instances

Use Godot's "Customizable Run Instance..." feature to run multiple servers and clients simultaneously for local testing.

### Feature Tags

Feature tags determine which role an instance plays:
- `client`: Runs as game client
- `gateway-server`: Runs as gateway server
- `master-server`: Runs as master server
- `world-server`: Runs as world server

### Headless Mode

Add `--headless` launch argument to servers to prevent empty windows.

## Important Files Reference

### Core Networking
- `source/common/network/wire.gd`: Wire type definitions
- `source/common/network/wire_codec.gd`: Binary encoding/decoding
- `source/common/network/endpoints/base_multiplayer_endpoint.gd`: Base networking class
- `source/common/registry/path_registry.gd`: Property path registry

### Server Components
- `source/server/gateway/gateway_main.gd`: Gateway server entry
- `source/server/master/master_main.gd`: Master server entry
- `source/server/world/world_main.gd`: World server entry
- `source/server/world/components/instance_manager.gd`: Instance management

### Client Components
- `source/client/client_main.gd`: Client entry point
- `source/client/autoload/client_state.gd`: Client state autoload
- `source/client/local_player/`: Local player controller

### Gameplay Systems
- `source/common/gameplay/characters/`: Character system
- `source/common/gameplay/combat/`: Combat system
- `source/common/gameplay/items/`: Item system
- `source/common/gameplay/maps/`: Map and instance system

## Common Tasks

### Adding a New Property to Sync

1. Register the property in `PathRegistry` (or use existing registration)
2. Add property to `ReplicatedProps` on the entity
3. Property will automatically sync via delta messages

### Creating a New Map Instance

1. Create `InstanceResource` in `source/common/gameplay/maps/instance/instance_collection/`
2. Create map scene in `source/common/gameplay/maps/maps/`
3. Add teleporter/warper to connect to other instances

### Adding a New Server-Side Command

1. Create command class in `source/server/world/components/chat_command/global_commands/`
2. Extend `ChatCommand` base class
3. Implement `execute()` method
4. Command will be automatically registered

## Resources

- **Documentation Website**: https://slayhorizon.github.io/godot-tiny-mmo/
- **Repository**: https://github.com/SlayHorizon/godot-tiny-mmo
- **Latest Research**: Byte-Level Networking Protocol for MMO Scalability

## Notes for AI Agents

1. **Always check existing patterns** before creating new code
2. **Use the unified codebase** - client and server share common code
3. **Respect the byte-packed protocol** - don't use string-based messages
4. **Server-authoritative** - all game logic should be validated server-side
5. **Instance-based** - players exist in specific instances, not globally
6. **PathRegistry** - use it for efficient property synchronization
7. **Feature tags** - understand which code runs on which instance type
