tool
extends EditorPlugin

var pluginUI

const FILE_BASED = true


const DEFAULT_PROJECT_OVERRIDE_SETTING = "application/config/project_settings_override"
const DEFAULT_PROJECT_SETTINGS_FILE = "project.godot"
const DEFAULT_OVERRIDE_SETTINGS_FILE = "override.cfg"
const DEFAULT_INPUT_SECTION = "input"

enum IMPORT_MODE {
	OVERRIDE = 0,
	ONLY_NEW,
	BREAK_ON_ERROR
}

func _enter_tree():
	pluginUI = preload("res://addons/portable-inputmap/portable-inputmap.tscn").instance()
	add_control_to_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT,pluginUI)

func _exit_tree():
	remove_control_from_container(CONTAINER_PROJECT_SETTING_TAB_RIGHT,pluginUI)
	pluginUI.free()

static func generic_error(code: int, format_strings : Array):
	var desc = ""
	match(code):
		100: desc = "loaded config has no "+str(DEFAULT_INPUT_SECTION)+" section!"
		101: desc = "loaded config has no keys in the "+str(DEFAULT_INPUT_SECTION)+" section!"
		102: desc = "key \"{str}\" has no value in the "+str(DEFAULT_INPUT_SECTION)+" section!".format({"str":format_strings[0]})
		103: desc = "key \"{str}\" has multiple values!".format({"str":format_strings[0]})
		104: desc = "corrupted header in binary file (not ECFG)"
		105: desc = "binary file not opened"
		106: desc = "{str} is a invalid mode flag. please check enum ModeFlags in File class.".format({"str":format_strings[0]})
		_: desc = "Error with code: "+str(code)+".See Enum Error for further details"
	print("[portable-inputmap][error]: "+desc)
	return false

static func get_current_project_inputmap(cfg_holder : Array):
	# the filebased function is always correct, but doesnt export ui_* when default
	# for the objectbased function project must be reloaded before changes apply, not the best option because you can lose data
	if FILE_BASED:
		return get_filebased_current_project_inputmap(cfg_holder)
	else:
		return get_objectbased_current_project_inputmap(cfg_holder)

static func get_filebased_current_project_inputmap(cfg_holder : Array):
	var settings_override = ProjectSettings.get_setting(DEFAULT_PROJECT_OVERRIDE_SETTING) as String
	if settings_override.empty():
		if !get_inputmap_from_file(DEFAULT_PROJECT_SETTINGS_FILE, cfg_holder):
			return false
	else:
		if !get_inputmap_from_file(settings_override, cfg_holder):
			return false
	
	if File.new().file_exists(DEFAULT_OVERRIDE_SETTINGS_FILE):
		var override_map = []
		if !get_inputmap_from_file(DEFAULT_OVERRIDE_SETTINGS_FILE, override_map):
			return false
		if !merge_inputmaps_by_mode(cfg_holder,override_map,IMPORT_MODE.OVERRIDE):
			return false
	return true

static func get_objectbased_current_project_inputmap(cfg_holder : Array):
	for action in InputMap.get_actions():
		var deadzone = InputMap.action_get_deadzone(action)
		var tmp = {
			key = action,
			value = {
				deadzone = deadzone,
				events = InputMap.get_action_list(action)
			}
		}
		cfg_holder.append(tmp)
	pass

static func get_inputmap_from_string(data : String, cfg_holder : Array):
	var last_err
	var config = ConfigFile.new()
	last_err = config.parse(data)
	if last_err != OK:
		return generic_error(last_err,[])
	return get_inputmap_from_configfile(config, cfg_holder)

static func file_open_wrapper(file_path : String, mode_flag: int, file: File):
	var last_err
	last_err = file.open(file_path,mode_flag)
	if last_err != OK:
		return generic_error(last_err,[])
	return true

static func check_valid_binaryfile(file: File):
	if !file.is_open():
		return generic_error(105,[])
	var header = file.get_buffer(4)
	if header.get_string_from_utf8() != "ECFG":
		return generic_error(104,[])
	return true

static func get_inputmap_from_binaryfile(file_path: String, cfg_holder: Array):
	var file = File.new()
	var count
	
	if !file_open_wrapper(file_path, File.READ, file):
		return false
	
	if !check_valid_binaryfile(file):
		return false
	
	count = file.get_32()
	
	for i in count:
		var key = file.get_buffer(file.get_32()).get_string_from_utf8()
		
		# TODO security warning, RCE possible while get_var
		var value = file.get_var(true)
		if key.begins_with(DEFAULT_INPUT_SECTION+"/"):
			var key_value_pair = {}
			key_value_pair.key = key.substr(str(DEFAULT_INPUT_SECTION+"/").length())
			key_value_pair.value = value
			cfg_holder.append(key_value_pair)
	file.close()
	return true

static func get_inputmap_from_file(file_path: String, cfg_holder: Array):
	if file_path.ends_with(".godot"):
		return get_inputmap_from_textfile(file_path,cfg_holder)
	elif file_path.ends_with(".binary"):
		return get_inputmap_from_binaryfile(file_path, cfg_holder)
	else:
		var file = File.new()
		if !file_open_wrapper(file_path,File.READ,file):
			return false
		if check_valid_binaryfile(file):
			file.close()
			return get_inputmap_from_binaryfile(file_path,cfg_holder)
		else:
			file.close()
			return get_inputmap_from_textfile(file_path,cfg_holder)

static func get_inputmap_from_textfile(file_path : String, cfg_holder : Array):
	var last_err
	var config = ConfigFile.new()
	last_err = config.load(file_path)
	if last_err != OK:
		return generic_error(last_err,[])
	return get_inputmap_from_configfile(config, cfg_holder)

static func get_inputmap_from_configfile(config: ConfigFile, cfg_holder : Array):
	if !config.has_section(DEFAULT_INPUT_SECTION):
		#this is not an "breaking" error but noticeable
		generic_error(100,[]);
		return true
	var keys = config.get_section_keys(DEFAULT_INPUT_SECTION);
	if keys.empty():
		return generic_error(101,[]);
	for key in keys:
		var value = config.get_value(DEFAULT_INPUT_SECTION,key as String,null)
		if value == null:
			return generic_error(102,[key as String]);
		var key_value_pair = {}
		key_value_pair.key = key
		key_value_pair.value = value
		cfg_holder.append(key_value_pair)
	return true

static func merge_inputmaps_by_mode(curr_map : Array, new_map : Array, pMode : int):
	for new_map_line in new_map:
		var found = false
		for curr_map_line in curr_map:
			if curr_map_line.key == new_map_line.key:
				found = true
				if pMode == IMPORT_MODE.OVERRIDE:
					curr_map_line.value = new_map_line.value
				if pMode == IMPORT_MODE.ONLY_NEW:
					break
				if pMode == IMPORT_MODE.BREAK_ON_ERROR:
					return generic_error(103,[curr_map_line.key as String])
		if !found: curr_map.append(new_map_line)
	return true

static func export_current_project_inputmap(file_path : String):
	var curr_config = []
	var config = ConfigFile.new()
	if !get_current_project_inputmap(curr_config):
		return false
	for config_line in curr_config:
		config.set_value(DEFAULT_INPUT_SECTION,config_line.key,config_line.value)
	var last_err = config.save(file_path)
	if  last_err != OK:
		return generic_error(last_err,[])
	return true

static func import_inputmap_from_file(file_path : String, mode : int):
	var last_err
	var curr_config = []
	var loaded_config = []
	var config = ConfigFile.new()
	
	if !get_current_project_inputmap(curr_config):
		return false
	if !get_inputmap_from_file(file_path,loaded_config):
		return false
	if !merge_inputmaps_by_mode(curr_config,loaded_config, mode):
		return false
	
	if File.new().file_exists(DEFAULT_OVERRIDE_SETTINGS_FILE):
		last_err = config.load(DEFAULT_OVERRIDE_SETTINGS_FILE)
		if last_err != OK:
			return generic_error(last_err,[])
		if config.has_section(DEFAULT_INPUT_SECTION):
			config.erase_section(DEFAULT_INPUT_SECTION)
			last_err = config.save(DEFAULT_OVERRIDE_SETTINGS_FILE)
			if last_err != OK:
				return generic_error(last_err,[])
			
	var settings_override = ProjectSettings.get_setting(DEFAULT_PROJECT_OVERRIDE_SETTING) as String
	if settings_override.empty():
		last_err = config.load(DEFAULT_PROJECT_SETTINGS_FILE)
		if last_err != OK:
			return generic_error(last_err,[])
		if config.has_section(DEFAULT_INPUT_SECTION):
			config.erase_section(DEFAULT_INPUT_SECTION)
		for config_line in curr_config:
			config.set_value(DEFAULT_INPUT_SECTION,config_line.key,config_line.value)
		last_err = config.save(DEFAULT_PROJECT_SETTINGS_FILE)
		if last_err != OK:
			return generic_error(last_err,[])
	else:
		last_err = config.load(settings_override)
		if last_err != OK:
			return generic_error(last_err,[])
		if config.has_section(DEFAULT_INPUT_SECTION):
			config.erase_section(DEFAULT_INPUT_SECTION)
		for config_line in curr_config:
			config.set_value(DEFAULT_INPUT_SECTION,config_line.key,config_line.value)
		last_err = config.save(settings_override)
		if last_err != OK:
			return generic_error(last_err,[])
	
	return true

static func import_button_click(pPath: String, pMode: int):
	return import_inputmap_from_file(pPath,pMode)

static func export_button_click(pPath: String):
	return export_current_project_inputmap(pPath)
