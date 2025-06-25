@tool
extends EditorPlugin


var plugin: EditorInspectorPlugin


func _enter_tree():
	foo()
	pass
	#plugin = preload("res://addons/tinymmo/inspector_plugin.gd").new()
	#add_inspector_plugin(plugin)


func _exit_tree():
	if plugin:
		remove_inspector_plugin(plugin)

func foo():
	var accept_dialog := AcceptDialog.new()
	accept_dialog.exclusive = true
	accept_dialog.title = "Welcome!"
	accept_dialog.dialog_text = "It seems it's the first time you run the project.\nDo you want to apply default debug setup?\nIt includes 2 different game servers, 2 clients and 1 master server."
	
	accept_dialog.add_cancel_button("No Thanks")
	
	accept_dialog.confirmed.connect(_on_accept_dialog_confirmed.bind(accept_dialog))
	accept_dialog.canceled.connect(accept_dialog.queue_free)
	
	EditorInterface.popup_dialog_centered(accept_dialog)


func _on_accept_dialog_confirmed(dialog: AcceptDialog) -> void:
	const RUN_INSTANCES_CONFIG: Array[Dictionary] = [
		{
			"arguments": "--headless",
			"features": "gateway-server",
			"override_args": false,
			"override_features": false
		}, {
			"arguments": "--headless",
			"features": "master-server",
			"override_args": false,
			"override_features": false
		}, {
			"arguments": "",
			"features": "world-server",
			"override_args": false,
			"override_features": false
		}, {
			"arguments": "--position 1940,40",
			"features": "client",
			"override_args": false,
			"override_features": false
		}, {
			"arguments": "--position 2800,400",
			"features": "client",
			"override_args": false,
			"override_features": false
		}, {
			"arguments": "--config=test_config/world_server_config_hardcore.cfg --headless",
			"features": "world-server",
			"override_args": false,
			"override_features": false
		}
	]
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()


	editor_settings.set_project_metadata(
		"debug_options",
		"run_instance_count",
		6.0
	)
	editor_settings.set_project_metadata(
		"debug_options",
		"run_instances_config",
		RUN_INSTANCES_CONFIG
	)
	dialog.queue_free()
	print(editor_settings.get_changed_settings())
	print(editor_settings.has_setting("run_instances_config"))
#	EditorInterface.restart_editor.call_deferred()
