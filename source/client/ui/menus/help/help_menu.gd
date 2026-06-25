extends MenuShell
## In-game help / onboarding reference. Static content, no server calls. Opened from the Help tile in the
## menu overlay, and pointed to by the first-run welcome modal. Edit HELP_TEXT to change the copy.


const HELP_TEXT: String = """[b]The short version[/b]
A hard, sandbox MMORPG. No forced path and no hand-holding. Explore, fight, build a guild, take territory. Finding your own footing is the point.

[b]Where to start[/b]
Talk to NPCs. The Hall Keeper near your starting cell has a first quest. NPCs offering quests are the main thread to pull when you want a direction.

[b]Guilds and territory[/b]
Join or found a guild, then take a territory by capturing its banner, and earn Glory for as long as your guild holds it. See the Guild and Leaderboard menus.

[b]Community and feedback[/b]
This is an alpha, so expect rough edges, and patch notes land in your Mailbox.
Found a bug or have an idea? Type /feedback in chat to send it straight to us.
Come say hi: join our [url=https://discord.gg/QE5JwpFzgK][color=#6cc5ff]Discord[/color][/url] or visit the [url=https://ekoniaonline.com][color=#6cc5ff]website[/color][/url]."""


func _ready() -> void:
	build_shell("Help", null, true)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_constant_override(&"line_separation", 5)
	label.text = HELP_TEXT
	# Clickable [url=...] links (Discord / website) open in the player's browser.
	label.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	scroll.add_child(label)

	# Drag the help text to scroll on touch/mouse; the label still receives link taps.
	DragScroll.enable(scroll)
