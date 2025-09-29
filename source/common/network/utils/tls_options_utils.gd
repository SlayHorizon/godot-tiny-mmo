class_name TLSOptionsUtils


static func create_server_tls_options(key_path: String, certificate_path: String) -> TLSOptions:
	var key: CryptoKey = CryptoKey.new()
	var error: Error = key.load(key_path)
	if error != OK:
		printerr("Failed loading key with error: %s" % error_string(error))
		return null

	var certificate := X509Certificate.new()
	error = certificate.load(certificate_path)
	if error != OK:
		printerr("Failed to load certificate with error: %s" % error_string(error))
		return null
	
	return TLSOptions.server(key, certificate)


static func create_client_tls_options(certificate_path: String) -> TLSOptions:
	var certificate := X509Certificate.new()
	var error: Error = certificate.load(certificate_path)
	if error != OK:
		printerr("Failed to load certificate with error: %s" % error_string(error))
	
	if OS.has_feature("enforcedtls"):
		return TLSOptions.client(certificate)
	else:
		return TLSOptions.client_unsafe(certificate)
