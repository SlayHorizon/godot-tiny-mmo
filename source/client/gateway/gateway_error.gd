class_name GatewayError

## Turns a gateway/auth error response into a localized, player-facing message.
##
## The gateway can return errors in three shapes: numeric codes (GatewayAPI.ERR_*
## or a Godot Error like ERR_TIMEOUT), short string tokens ("invalid_payload",
## "connection_failed", …), or already-human server strings (the version gate,
## server-side validation messages). This collapses all of them to one readable
## line and — crucially — NEVER returns a raw dictionary dump, so the UI can't
## show a player `{ "error": 50 }`. Unknown shapes fall back to ERR_GENERIC.
static func humanize(response: Dictionary) -> String:
	var code: Variant = response.get("error", null)

	if code is String:
		match code:
			"request_error", "connection_failed":
				return TranslationServer.translate("ERR_CONNECTION")
			"invalid_payload", "bad_response":
				return TranslationServer.translate("ERR_GENERIC")
			_:
				# An already-human server message (version gate, validation text).
				# Passed through as-is; localizing these is a separate server-side
				# pass (the server would need to send keys instead of English).
				return code

	# Nested {code, message} from CredentialsUtils (character/account validation).
	if code is Dictionary:
		var message: String = str(code.get("message", ""))
		if message.is_empty():
			return TranslationServer.translate("ERR_GENERIC")
		return message

	if code is int or code is float:
		match int(code):
			GatewayAPI.ERR_BAD_CREDENTIALS:
				return TranslationServer.translate("ERR_BAD_CREDENTIALS")
			GatewayAPI.ERR_ALREADY_CONNECTED:
				return TranslationServer.translate("ERR_ALREADY_CONNECTED")
			GatewayAPI.ERR_RATE_LIMITED:
				return TranslationServer.translate("ERR_RATE_LIMITED")
			GatewayAPI.ERR_ACCOUNT_CREATE_FAILED:
				return TranslationServer.translate("ERR_ACCOUNT_CREATE_FAILED")
			GatewayAPI.ERR_OUTDATED_VERSION:
				return TranslationServer.translate("ERR_OUTDATED")
			Error.ERR_TIMEOUT:
				return TranslationServer.translate("ERR_CONNECTION")
			_:
				return TranslationServer.translate("ERR_GENERIC")

	return TranslationServer.translate("ERR_GENERIC")


## True when the error looks like the gateway simply wasn't reachable (worth a
## retry), as opposed to a real rejection like bad credentials. Used by
## auto-login to ride out the editor's all-at-once boot race.
static func is_connection_error(response: Dictionary) -> bool:
	var code: Variant = response.get("error", null)
	if code is String:
		return code == "connection_failed" or code == "request_error"
	if code is int or code is float:
		return int(code) == Error.ERR_TIMEOUT
	return false
