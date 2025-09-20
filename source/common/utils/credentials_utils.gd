extends RefCounted


const USERNAME_MIN_LEN: int = 3
const USERNAME_MAX_LEN: int = 20
const USERNAME_RESERVED: PackedStringArray = ["admin", "moderator", "guest"]

const PASSWORD_MIN_LEN: int = 6
const PASSWORD_MAX_LEN: int = 32

enum UsernameError {
	OK,
	EMPTY,
	TOO_SHORT,
	TOO_LONG,
	INVALID_CHARS,
	RESERVED,
	
}


static func is_valid_username(username: String) -> bool:
	if username.is_empty():
		return false
	return true


static func validate_username(username: String) -> Dictionary:
	if username.is_empty():
		return _fail(UsernameError.EMPTY, "Username required.")
	if username.length() < USERNAME_MIN_LEN:
		return _fail(UsernameError.TOO_SHORT, "Min %d characters." % USERNAME_MIN_LEN)
	if username.length() > USERNAME_MAX_LEN:
		return _fail(UsernameError.TOO_LONG, "Max %d characters." % USERNAME_MAX_LEN)
	if not username.is_valid_ascii_identifier():
		return _fail(UsernameError.INVALID_CHARS, "Use letters, digits, underscore.")
	if USERNAME_RESERVED.has(username.to_lower()):
		return _fail(UsernameError.RESERVED, "This name is reserved.")
	return {"code": UsernameError.OK, "message": ""}


static func validate_password(password: String) -> Dictionary:
	if password.is_empty():
		return _fail(UsernameError.EMPTY, "Password required.")
	if password.length() < PASSWORD_MIN_LEN:
		return _fail(UsernameError.TOO_SHORT, "Min %d characters." % PASSWORD_MIN_LEN)
	if password.length() > PASSWORD_MAX_LEN:
		return _fail(UsernameError.TOO_LONG, "Max %d characters." % PASSWORD_MAX_LEN)
	if not password.is_valid_ascii_identifier():
		return _fail(UsernameError.INVALID_CHARS, "Use letters, digits, underscore.")
	return {"code": UsernameError.OK, "message": ""}


static func _fail(code: UsernameError, message: String) -> Dictionary:
	return {"code": code, "message": message}
