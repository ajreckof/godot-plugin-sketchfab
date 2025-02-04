extends SceneTree

const ARG_PREFIX = "--zip-to-unpack "

func _init():
	print("Unzipper started")

	var zip_path
	for arg in OS.get_cmdline_args():
		if arg.begins_with(ARG_PREFIX):
			zip_path = arg.right(arg.length() - ARG_PREFIX.length())
			break

	if !zip_path:
		print("No file specified")
		return

	print("Unpacking %s..." % zip_path)

	if !ProjectSettings.load_resource_pack(zip_path):
		print(zip_path)
		print("Package file not found")
		return

	var name_regex = RegEx.new()
	name_regex.compile("([^/\\\\]+)\\.zip")
	var base_name = name_regex.search(zip_path).get_string(1)

	var out_path = zip_path.left(zip_path.find(base_name)) + base_name + "/"
	DirAccess.make_dir_absolute(out_path)
	unpack_dir("res://", out_path)

	print("Done!")

func unpack_dir(src_path, out_path):
	print("DirAccess: %s -> %s" % [src_path, out_path])

	var dir = DirAccess.open(src_path)
	dir.list_dir_begin()  
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			var new_src_path = "%s%s/" % [src_path, file_name]
			var new_out_path = "%s%s/" % [out_path, file_name]
			DirAccess.make_dir_absolute(new_out_path)
			unpack_dir(new_src_path, new_out_path)
		else:
			var file_src_path = "%s%s" % [src_path, file_name]
			var file_out_path = "%s%s" % [out_path, file_name]
			print("File: %s -> %s" % [file_src_path, file_out_path])
			var file = FileAccess.open(file_src_path, FileAccess.READ)
			var data = file.get_buffer(file.get_length())
			file.close()
			file = FileAccess.open(file_out_path, FileAccess.WRITE)
			file.store_buffer(data)
			file.close()
		file_name = dir.get_next()
