class_name PasswordHasher

## Salted, key-stretched password hashing for account storage. GDScript has no
## built-in bcrypt/Argon2, so this is iterated SHA-256 with a per-account random
## salt — vastly better than plaintext and good enough for alpha. The stored
## string is self-describing ("sha256$<iters>$<salt_b64>$<hash_b64>"), so the
## iteration count can be raised later without breaking existing hashes.

const _ALGO: String = "sha256"
# Tunable. ~100k SHA-256 rounds adds real cost to offline cracking while staying
# well under a frame's worth of latency for an (infrequent) login.
const _ITERATIONS: int = 100000
const _SALT_BYTES: int = 16


## Hash a plaintext password for storage. Each call uses a fresh random salt, so
## the same password produces different stored values.
static func hash_password(password: String) -> String:
	var salt: PackedByteArray = Crypto.new().generate_random_bytes(_SALT_BYTES)
	var digest: PackedByteArray = _derive(password, salt, _ITERATIONS)
	return "%s$%d$%s$%s" % [
		_ALGO,
		_ITERATIONS,
		Marshalls.raw_to_base64(salt),
		Marshalls.raw_to_base64(digest),
	]


## Verify a plaintext password against a stored hash string. Returns false on any
## malformed/unknown stored value rather than throwing.
static func verify(password: String, stored: String) -> bool:
	var parts: PackedStringArray = stored.split("$")
	if parts.size() != 4 or parts[0] != _ALGO:
		return false
	var iterations: int = parts[1].to_int()
	if iterations <= 0:
		return false
	var salt: PackedByteArray = Marshalls.base64_to_raw(parts[2])
	var expected: PackedByteArray = Marshalls.base64_to_raw(parts[3])
	var actual: PackedByteArray = _derive(password, salt, iterations)
	return _constant_time_equal(actual, expected)


## Iterated SHA-256 over (salt || running-digest). One reused HashingContext to
## avoid allocating per round.
static func _derive(password: String, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var digest: PackedByteArray = salt.duplicate()
	digest.append_array(password.to_utf8_buffer())
	var ctx: HashingContext = HashingContext.new()
	for _i in iterations:
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(salt)
		ctx.update(digest)
		digest = ctx.finish()
	return digest


## Length-independent compare so verification time doesn't leak how many bytes
## matched.
static func _constant_time_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff: int = 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0
