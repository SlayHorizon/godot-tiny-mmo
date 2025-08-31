@tool
extends EditorPlugin


const MAIN_PANEL = preload("res://addons/tinymmo/main_screen/main_panel.tscn")

var plugin: EditorInspectorPlugin
var export_plugin: EditorExportPlugin

var main_panel_instance: Control


func _enter_tree():
	# Main Screen
	main_panel_instance = MAIN_PANEL.instantiate()
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	main_panel_instance.hide()
	
	# Export Plugin
	export_plugin = preload("res://addons/tinymmo/export_plugin/export_plugin.gd").new()
	add_export_plugin(export_plugin)
	
	# Old code
	#foo()
	#plugin = preload("res://addons/tinymmo/inspector_plugin.gd").new()
	#add_inspector_plugin(plugin)


func _exit_tree():
	if main_panel_instance:
		main_panel_instance.queue_free()
	remove_export_plugin(export_plugin)
	if plugin:
		remove_inspector_plugin(plugin)


func _has_main_screen() -> bool:
	return true


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("MultiplayerSpawner", "EditorIcons")


func _get_plugin_name():
	return "TinyMMO"


func _make_visible(visible: bool) -> void:
	main_panel_instance.visible = visible

# OLD CODE
#func foo():
	#var accept_dialog := AcceptDialog.new()
	#accept_dialog.exclusive = true
	#accept_dialog.title = "Welcome!"
	#accept_dialog.dialog_text = "It seems it's the first time you run the project.\nDo you want to apply default debug setup?\nIt includes 2 different game servers, 2 clients and 1 master server."
	#
	#accept_dialog.add_cancel_button("No Thanks")
	#
	#accept_dialog.confirmed.connect(_on_accept_dialog_confirmed.bind(accept_dialog))
	#accept_dialog.canceled.connect(accept_dialog.queue_free)
	#
	#EditorInterface.popup_dialog_centered(accept_dialog)
#
#
#func _on_accept_dialog_confirmed(dialog: AcceptDialog) -> void:
	#const RUN_INSTANCES_CONFIG: Array[Dictionary] = [
		#{
			#"arguments": "--headless",
			#"features": "gateway-server",
			#"override_args": false,
			#"override_features": false
		#}, {
			#"arguments": "--headless",
			#"features": "master-server",
			#"override_args": false,
			#"override_features": false
		#}, {
			#"arguments": "",
			#"features": "world-server",
			#"override_args": false,
			#"override_features": false
		#}, {
			#"arguments": "--position 1940,40",
			#"features": "client",
			#"override_args": false,
			#"override_features": false
		#}, {
			#"arguments": "--position 2800,400",
			#"features": "client",
			#"override_args": false,
			#"override_features": false
		#}, {
			#"arguments": "--config=data/config/world_server_config_hardcore.cfg --headless",
			#"features": "world-server",
			#"override_args": false,
			#"override_features": false
		#}
	#]
	#var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
#
#
	#editor_settings.set_project_metadata(
		#"debug_options",
		#"run_instance_count",
		#6.0
	#)
	#editor_settings.set_project_metadata(
		#"debug_options",
		#"run_instances_config",
		#RUN_INSTANCES_CONFIG
	#)
	#dialog.queue_free()
	#print(editor_settings.get_changed_settings())
	#print(editor_settings.has_setting("run_instances_config"))
#	EditorInterface.restart_editor.call_deferred()
