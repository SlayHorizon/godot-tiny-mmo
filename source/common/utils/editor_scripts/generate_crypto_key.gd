@tool
extends EditorScript


# Called when the script is executed (using File -> Run in Script Editor).
func _run() -> void:
	if not DirAccess.dir_exists_absolute("res://bin"):
		DirAccess.make_dir_absolute("res://bin")
	generate_crypto_key_and_certificate()
	EditorInterface.get_resource_filesystem().scan()

## Example of how to create a crypto key with its self signed certificate.
## The private key shouldn't be exported on the client machine.
## Files generated are stored at res://bin.
func generate_crypto_key_and_certificate() -> void:
	var crypto = Crypto.new()
	var key = CryptoKey.new()
	var cert = X509Certificate.new()
	key = crypto.generate_rsa(4096)
	cert = crypto.generate_self_signed_certificate(key, "CN=example.com,O=A Game Company,C=IT")
	key.save("res://bin/server_key.key")
	cert.save("res://bin/server_certificate.crt")
