@tool
extends Window

const SafeData = preload("res://addons/sketchfab/SafeData.gd")
const Utils = preload("res://addons/sketchfab/Utils.gd")
const Requestor = preload("res://addons/sketchfab/Requestor.gd")
const Api = preload("res://addons/sketchfab/Api.gd")

var api = Api.new()
var downloader

@onready var label_model = find_child("Model")
@onready var label_user = find_child("User")
@onready var image = find_child("Image")

@onready var info = find_child("Info")
@onready var license = find_child("License")

@onready var download = find_child("Download")
@onready var progress = find_child("ProgressBar")
@onready var size_label = find_child("Size")

var uid
var imported_path
var view_url
var download_url
var download_size

func set_uid(uid):
	self.uid = uid

func _ready():
	$All.visible = false

func _on_about_to_show():
	if !uid:
		hide()
		return

	# Setup download button

	if Api.get_token():
		# Request download link

		var result = await api.request_download(uid)
		if !get_tree():
			return

		if typeof(result) == TYPE_INT && result == Api.SymbolicErrors.NOT_AUTHORIZED:
			OS.alert("Your session may have expired. Please log in again.", "Not authorized")
			hide()
			return

		if typeof(result) != TYPE_DICTIONARY:
			hide()
			return

		var gtlf = SafeData.dictionary(result, "gltf")
		if !gtlf.size():
			OS.alert("This model has not a glTF version.", "Sorry")
			hide()
			return

		download_url = SafeData.string(gtlf, "url")
		download_size = SafeData.integer(gtlf, "size")
		if !download_url:
			hide()
			return

		download.text = "Download (%.1f MiB)" % [download_size / (1024 * 1024)]
	else:
		download.text = "To download models you need to be logged in."
		download.disabled = true

	# Populate other information

	var data = await api.get_model_detail(uid)
	if typeof(data) != TYPE_DICTIONARY:
		hide()
		return

	label_model.text = SafeData.string(data, "name")

	var user = SafeData.dictionary(data, "user")
	label_user.text = "by %s" % SafeData.string(user, "displayName")

	view_url = SafeData.string(data, "viewerUrl")

	var thumbnails = SafeData.dictionary(data, "thumbnails")
	var images = SafeData.array(thumbnails, "images")
	image.max_size = size.x
	$All.size = size
	image.url = Utils.get_best_size_url(images, image.max_size, SafeData)

	var vc = SafeData.integer(data, "vertexCount")
	var fc = SafeData.integer(data, "faceCount")
	var ac = SafeData.integer(data, "animationCount")
	info.text = (
		"Vertex count: %.1fk\n" +
		"Face count: %.1fk\n" +
		"Animation: %s") % [
			vc * 0.001,
			fc * 0.001,
			"Yes" if ac else "No",
		]

	var license_data = SafeData.dictionary(data, "license")
	license.text = "%s\n(%s)" % [
		SafeData.string(license_data, "fullName"),
		SafeData.string(license_data, "requirements"),
	]
	$All.visible = true

func _on_Download_pressed():
	if imported_path:
		var ei = get_tree().get_meta("__editor_interface")
		ei.open_scene_from_path(imported_path)
		hide()
		return

	# Download file

	download.visible = false
	progress.value = 0
	progress.max_value = download_size
	progress.visible = true
	size_label.visible = true
	size_label.text = "    %.1f MiB" % (download_size / (1024 * 1024))

	var host_idx = download_url.find("//") + 2
	var path_idx = download_url.find("/", host_idx)
	var host = download_url.substr(host_idx, path_idx - host_idx)

	var path = download_url.right(download_url.length() - path_idx)
	downloader = Requestor.new(host)

	DirAccess.make_dir_absolute("res://sketchfab")

	var file_regex = RegEx.new()
	file_regex.compile("[^/]+?\\.zip")
	var filename = file_regex.search(download_url).get_string()
	var zip_path = "res://sketchfab/%s" % filename

	downloader.download_progressed.connect(_on_download_progressed)
	downloader.request(path, null, { "download_to": zip_path })
	var result = await downloader.completed
	if !result:
		return
	downloader.term()
	downloader = null

	if !result.ok:
		print("result.code : ", result.code)
		download.visible = true
		progress.visible = false
		size_label.visible = false
		OS.alert(
			"Please check your network connectivity, free disk space and try again.",
			"Download error")
		return

	# Unpack

	progress.show_percentage = false
	size_label.text = "    Model downloaded! Unpacking..."
	await get_tree().process_frame
	if !get_tree():
		return

	var out = []
	OS.execute(OS.get_executable_path(), [
		"-s", ProjectSettings.globalize_path("res://addons/sketchfab/unzip.gd"),
		"--zip-to-unpack %s" % ProjectSettings.globalize_path(zip_path),
		"--no-window",
		"--quit",
	], out)
	print(out[0])

	size_label.text = "    Model unpacked into project!"

	# Import and open

	var base_name = filename.substr(0, filename.find(".zip"))
	imported_path = "res://sketchfab/%s/scene.gltf" % base_name
	var ei = get_tree().get_meta("__editor_interface")
	ei.get_resource_filesystem().scan()
	while ei.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
		if !get_tree():
			return
	ei.select_file(imported_path)

	progress.visible = false
	size_label.visible = false
	download.visible = true
	download.text = "OPEN IMPORTED MODEL"

func _on_download_progressed(bytes, total_bytes):
	if !get_tree():
		downloader.term()
	progress.value = bytes

func _on_ViewOnSite_pressed():
	OS.shell_open(view_url)
