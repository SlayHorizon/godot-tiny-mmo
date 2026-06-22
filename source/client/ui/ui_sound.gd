class_name UISound
## Shared UI sound cues for the IN-GAME interface, routed through the AudioManager's polyphonic UI
## player — the same Sound bus + settings-bound volume the gateway uses. Static: call UISound.click()
## etc. from anywhere; the HUD auto-wires button taps/hovers to these. No-ops when audio isn't up (a
## headless / muted test client frees the AudioManager). Cue files live in assets/audio/sfx/ui/.
##
## The in-game UI fires a LOT (every button under the HUD), so each cue is trimmed a few dB under the
## bus volume here — softer than the gateway's deliberate, sparser clicks. Tune the *_DB consts.

const CLICK: String = "res://assets/audio/sfx/ui/ui_click.wav"
const BACK: String = "res://assets/audio/sfx/ui/ui_back.wav"
const HOVER: String = "res://assets/audio/sfx/ui/ui_hover.wav"
const REVEAL: String = "res://assets/audio/sfx/ui/ui_reveal.wav"

## Per-cue trim (dB under bus volume). Hover fires on every mouse-over, so it's the quietest.
const CLICK_DB: float = -6.0
const BACK_DB: float = -6.0
const HOVER_DB: float = -11.0
const REVEAL_DB: float = -6.0


static func play(path: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if is_instance_valid(Client) and Client.audio_manager != null:
		Client.audio_manager.play_ui_sound(path, pitch, volume_db)


static func click() -> void: play(CLICK, 1.0, CLICK_DB)
static func back() -> void: play(BACK, 1.0, BACK_DB)
static func hover() -> void: play(HOVER, 1.0, HOVER_DB)
static func reveal() -> void: play(REVEAL, 1.0, REVEAL_DB)
