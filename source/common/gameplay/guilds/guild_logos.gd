class_name GuildLogos
## Single source of truth for the guild emblem catalog. Logo ids are INDEXES
## into PATHS, persisted on guilds and synced in flag payloads — so entries are
## APPEND-ONLY (reordering or removing would repoint every guild's emblem).
## Textures load lazily at runtime (the server validates ids but never loads
## art). Was duplicated across guild_menu / guild_hall / territory_flag before
## the catalog grew past four (2026-07-19).

const PATHS: PackedStringArray = [
	"res://assets/sprites/guild_logos/wyvern.png",
	"res://assets/sprites/guild_logos/kawaii_skull.png",
	"res://assets/sprites/guild_logos/cute_crown.png",
	"res://assets/sprites/guild_logos/cute_fish.png",
	"res://assets/sprites/guild_logos/wolf.png",
	"res://assets/sprites/guild_logos/crossed_swords.png",
	"res://assets/sprites/guild_logos/oak.png",
	"res://assets/sprites/guild_logos/moon.png",
	"res://assets/sprites/guild_logos/anchor.png",
	"res://assets/sprites/guild_logos/hammer.png",
	"res://assets/sprites/guild_logos/mushroom.png",
	"res://assets/sprites/guild_logos/sun.png",
	"res://assets/sprites/guild_logos/raven.png",
]


static func count() -> int:
	return PATHS.size()


## Emblem texture for [param logo_id], clamped to the catalog (bad ids render
## the default emblem instead of crashing). Client-side only.
static func texture(logo_id: int) -> Texture2D:
	var idx: int = clampi(logo_id, 0, PATHS.size() - 1)
	return load(PATHS[idx]) as Texture2D
