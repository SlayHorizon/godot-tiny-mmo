class_name FileUtils


static func get_all_file_at(
	path: String,
	pattern: String = "*",
	recursive: bool = true
) -> PackedStringArray:
	var result_files: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(path)

	if not dir:
		push_error("Failed to open directory at %s with error %s" % [
			path, error_string(DirAccess.get_open_error())
		])
		return result_files

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name:
		var full_path: String = path.path_join(file_name)
		if dir.current_is_dir() and recursive:
			# Forward pattern + recursive so subdirs respect the same filter.
			result_files += get_all_file_at(full_path, pattern, recursive)
		else:
			# Exported projects expose resources via .remap (and imported
			# assets via .import) sidecars instead of the original filename.
			# Strip those suffixes so callers see the canonical res:// path
			# they can feed to ResourceLoader, and so `*.tres` etc. match.
			var canonical_name: String = file_name
			if canonical_name.ends_with(".remap"):
				canonical_name = canonical_name.trim_suffix(".remap")
			elif canonical_name.ends_with(".import"):
				canonical_name = canonical_name.trim_suffix(".import")
			if canonical_name.match(pattern):
				result_files.append(path.path_join(canonical_name))
		file_name = dir.get_next()

	dir.list_dir_end()
	return result_files
