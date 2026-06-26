extends EditorExportPlugin
## Export adjustments for the client/server split.
##
## CLIENT exports — server-class stubbing:
## Godot force-exports every .gd in the project regardless of preset filters, so
## the real `source/server/*` scripts always ended up in client builds — where
## they fail to parse (SQLite GDExtension absent) and cascade-break every
## dependent script. This plugin REPLACES each server script at export time with
## a reflection-generated stub:
##   - class_name + extends preserved → the global class cache resolves, so
##     common/ code may freely TYPE server classes.
##   - constants/enums copied VERBATIM (faithful values — no silent divergence).
##   - signals/vars declared, untyped.
##   - methods keep name/arity but drop ALL type annotations (this is what makes
##     `_init(_db: SQLite)` safe — stubs never name SQLite); public bodies
##     push_error if a client ever calls one (a missing is_server() gate is a
##     screaming log line, not silence).
##
## IMPORTANT: replacement happens in _export_file (skip + add_file), which only
## fires for files in the export set — so client presets must use an
## "export all resources" style mode, NOT a curated allowlist (allowlist mode
## force-adds scripts through a side path that bypasses plugins, shipping the
## REAL script alongside the stub — the duplicate wins and the cascade returns).
##
## SERVER exports: untouched. Client autoloads stay registered — they self-free
## via `OS.has_feature("client")`.

const SERVER_ROOT: String = "res://source/server/"
const SQLITE_ADDON_ROOT: String = "res://addons/godot-sqlite/"

var _stub_count: int = 0
var _client_export: bool = false


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_client_export = features.has("client")
	_stub_count = 0
	if not _client_export:
		print("Server export: real source/server scripts ship; client autoloads self-free via OS.has_feature(\"client\").")


func _export_file(path: String, _type: String, features: PackedStringArray) -> void:
	if not features.has("client"):
		return
	# The sqlite GDExtension never ships to clients (server-only dependency).
	if path.begins_with(SQLITE_ADDON_ROOT):
		skip()
		return
	if not path.begins_with(SERVER_ROOT):
		return
	if path.ends_with(".gd"):
		var stub: String = _generate_stub(path)
		skip() # drop the real script either way — broken-but-present is worse
		if stub.is_empty():
			push_error("Stub generator failed for %s — client code naming this class will break." % path)
		else:
			add_file(path, stub.to_utf8_buffer(), false)
			_stub_count += 1
	else:
		# Server-only scenes/resources/configs never ship.
		skip()


func _export_end() -> void:
	if _client_export:
		print("Client export: replaced %d server scripts with generated stubs." % _stub_count)
		if _stub_count == 0:
			push_warning("Export plugin replaced 0 server scripts — is the preset using an 'export all resources' mode? (Allowlist mode bypasses _export_file for scripts.)")


func _get_name() -> String:
	# Export plugins run in NAME-SORTED order (editor_export_platform.cpp:
	# "Always sort by name" + godot#93487), and the engine's script tokenizer
	# is itself a plugin named "GDScript" that CLAIMS every .gd (remap + break)
	# in binary-token mode. The "AAA_" prefix sorts us BEFORE it, so we replace
	# server scripts first and the tokenizer processes everything else normally
	# — which is what lets the presets keep script_export_mode = binary tokens.
	# (Same trick dalexeev's gdscript-preprocessor uses.)
	return "AAA_server_class_stubs"


## Builds the stub source for one server script using reflection — no text
## parsing (the editor context has every class loaded, including SQLite).
func _generate_stub(path: String) -> String:
	var script: GDScript = load(path) as GDScript
	if script == null:
		return ""

	var out: PackedStringArray = []
	var gname: StringName = script.get_global_name()
	if gname != &"":
		out.append("class_name %s" % gname)
	out.append("extends %s" % _base_name(script))
	out.append("## AUTO-GENERATED CLIENT STUB — the real script is server-only.")
	out.append("## Generated at export by addons/tinymmo/export_plugin/export_plugin.gd.")
	out.append("")

	# Inherited members must not be re-declared (parse error) — collect the
	# base chain's signals/consts/vars to subtract. Methods MAY re-declare
	# (legal override), so they need no subtraction.
	var base: GDScript = script.get_base_script()
	var base_signals: Dictionary = {}
	var base_props: Dictionary = {}
	var base_consts: Dictionary = {}
	if base != null:
		for s: Dictionary in base.get_script_signal_list():
			base_signals[s["name"]] = true
		for p: Dictionary in base.get_script_property_list():
			base_props[p["name"]] = true
		for c: String in base.get_script_constant_map():
			base_consts[c] = true

	# --- signals ---
	for s: Dictionary in script.get_script_signal_list():
		if base_signals.has(s["name"]):
			continue
		var args: PackedStringArray = []
		for a: Dictionary in s.get("args", []):
			args.append(str(a.get("name", "arg")))
		out.append("signal %s(%s)" % [s["name"], ", ".join(args)])

	# --- constants (enums arrive as Dictionaries; values copied verbatim) ---
	var consts: Dictionary = script.get_script_constant_map()
	for cname: String in consts:
		if base_consts.has(cname):
			continue
		var value: Variant = consts[cname]
		if value is GDScript:
			# Inner class: a parseable placeholder keeps `Outer.Inner` valid.
			out.append("class %s:" % cname)
			out.append("\tpass")
		elif value is Object:
			# Preloaded resource or similar — the asset may be excluded from the
			# client build, so don't reference it.
			out.append("const %s = null # stub: server-only object constant" % cname)
		else:
			out.append("const %s = %s" % [cname, var_to_str(value)])

	# --- static vars (reflection lists these inconsistently vs consts/methods, so scan
	# the source). Emit them TYPED — unlike the instance vars below — so common code can
	# write `WorldServer.curr.method()` with full type-checking (the whole point of the
	# stub: typed server references from anywhere, no ServerHub-style Node indirection).
	# Defaults are stripped (they may call server-only code / preload excluded resources).
	# Caveat: a static var typed as a server-only-dependency class (e.g. an SQLite handle)
	# would re-name that type here — none exist today; revisit if one ever does.
	var static_names: Dictionary = {}
	for raw_line: String in script.source_code.split("\n", false):
		var sline: String = raw_line.strip_edges()
		if not sline.begins_with("static var "):
			continue
		var decl: String = sline.trim_prefix("static var ")
		var hash_idx: int = decl.find("#")
		if hash_idx != -1:
			decl = decl.substr(0, hash_idx)
		var eq_idx: int = decl.find("=")
		if eq_idx != -1:
			decl = decl.substr(0, eq_idx)
		decl = decl.strip_edges().trim_suffix(":").strip_edges()
		var var_name: String = decl.split(":")[0].strip_edges()
		if var_name.is_empty() or static_names.has(var_name):
			continue
		static_names[var_name] = true
		out.append("static var %s" % decl)

	# --- instance vars (untyped: this is what erases SQLite & friends from declarations) ---
	for p: Dictionary in script.get_script_property_list():
		if not (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if base_props.has(p["name"]):
			continue
		if static_names.has(p["name"]): # already declared as a static var above
			continue
		out.append("var %s" % p["name"])

	out.append("")

	# --- methods: same name/arity, params untyped with null defaults so any call
	# site parses. Public methods are LOUD when reached on a client build;
	# engine-lifecycle (_underscore) methods stay silent (stub nodes that land in
	# a tree should simply be inert).
	var seen: Dictionary = {}
	for m: Dictionary in script.get_script_method_list():
		var mname: String = m["name"]
		if seen.has(mname) or mname.begins_with("@"):
			continue
		seen[mname] = true
		var params: PackedStringArray = []
		for a: Dictionary in m.get("args", []):
			params.append("%s = null" % str(a.get("name", "arg")))
		var prefix: String = "static " if (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) else ""
		out.append("%sfunc %s(%s):" % [prefix, mname, ", ".join(params)])
		if mname.begins_with("_"):
			out.append("\treturn null")
		else:
			out.append("\tpush_error(\"Client build called server-only %s.%s() — missing an is_server() gate?\")" % [
				gname if gname != &"" else path.get_file(), mname
			])
			out.append("\treturn null")
		out.append("")

	return "\n".join(out)


func _base_name(script: GDScript) -> String:
	var base: GDScript = script.get_base_script()
	if base != null:
		var bg: StringName = base.get_global_name()
		if bg != &"":
			return bg # another server class — its stub ships too, chain resolves
	return script.get_instance_base_type() # native base (Node, RefCounted, ...)
