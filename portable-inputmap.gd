tool
extends EditorPlugin

var pluginUI

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

static func generic_error(pCode: int, pFormatStrings : Array):
	var desc = ""
	match(pCode):
		100: desc = "loaded config has no "+str(DEFAULT_INPUT_SECTION)+" section!"
		101: desc = "loaded config has no keys in the "+str(DEFAULT_INPUT_SECTION)+" section!"
		102: desc = "key \"{str}\" has no value in the "+str(DEFAULT_INPUT_SECTION)+" section!".format({"str":pFormatStrings[0]})
		103: desc = "key \"{str}\" has multiple values!".format({"str":pFormatStrings[0]})
		_: desc = "Error with code: "+str(pCode)+".See Enum Error for further details"
	print("[portable-inputmap][error]: "+desc)
	return false

static func get_filebased_current_project_inputmap(pCfgHolder : Array):
	# the filebased function is always correct, but doesnt export ui_* when default
	# check for settings override
	var settings_override = ProjectSettings.get_setting(DEFAULT_PROJECT_OVERRIDE_SETTING) as String
	if settings_override.empty():
		if !get_inputmap_from_file(DEFAULT_PROJECT_SETTINGS_FILE, pCfgHolder):
			return false
	else:
		if !get_inputmap_from_file(settings_override, pCfgHolder):
			return false
	
	if File.new().file_exists(DEFAULT_OVERRIDE_SETTINGS_FILE):
		var override_map = []
		if !get_inputmap_from_file(DEFAULT_OVERRIDE_SETTINGS_FILE, override_map):
			return false
		if !merge_inputmaps_by_mode(pCfgHolder,override_map,IMPORT_MODE.OVERRIDE):
			return false
	return true
static func get_objectbased_current_project_inputmap(pCfgHolder : Array):
	# project must be reloaded before changes apply, not the best option because you can lose data
	for action in InputMap.get_actions():
		var deadzone = InputMap.action_get_deadzone(action)
		var tmp = {
			key = action,
			value = {
				deadzone = deadzone,
				events = InputMap.get_action_list(action)
			}
		}
		pCfgHolder.append(tmp)
	pass
static func get_inputmap_from_string(pData : String, pCfgHolder : Array):
	var last_err
	var config = ConfigFile.new()
	last_err = config.parse(pData)
	if last_err != OK:
		return generic_error(last_err,[])
	return get_inputmap_from_configfile(config, pCfgHolder)
static func get_inputmap_from_file(pFilePath : String, pCfgHolder : Array):
	var last_err
	var config = ConfigFile.new()
	last_err = config.load(pFilePath)
	if last_err != OK:
		return generic_error(last_err,[])
	return get_inputmap_from_configfile(config, pCfgHolder)
static func get_inputmap_from_configfile(pConfig: ConfigFile, pCfgHolder : Array):
	if !pConfig.has_section(DEFAULT_INPUT_SECTION):
		#this is not an "breaking" error but noticeable
		generic_error(100,[]);
		return true
	var keys = pConfig.get_section_keys(DEFAULT_INPUT_SECTION);
	if keys.empty():
		return generic_error(101,[]);
	for key in keys:
		var value = pConfig.get_value(DEFAULT_INPUT_SECTION,key as String,null)
		if value == null:
			return generic_error(102,[key as String]);
		var KeyValuePair = {}
		KeyValuePair.key = key
		KeyValuePair.value = value
		pCfgHolder.append(KeyValuePair)
	return true
static func merge_inputmaps_by_mode(pCurrMap : Array, pNewMap : Array, pMode : int):
	for new_map_line in pNewMap:
		var found = false
		for curr_map_line in pCurrMap:
			if curr_map_line.key == new_map_line.key:
				found = true
				if pMode == IMPORT_MODE.OVERRIDE:
					curr_map_line.value = new_map_line.value
				if pMode == IMPORT_MODE.ONLY_NEW:
					break
				if pMode == IMPORT_MODE.BREAK_ON_ERROR:
					return generic_error(103,[curr_map_line.key as String])
		if !found: pCurrMap.append(new_map_line)
	return true
static func export_current_project_inputmap(pFilePath : String):
	var curr_config = []
	var config = ConfigFile.new()
	if !get_filebased_current_project_inputmap(curr_config):
		return false
	for config_line in curr_config:
		config.set_value(DEFAULT_INPUT_SECTION,config_line.key,config_line.value)
	var last_err = config.save(pFilePath)
	if  last_err != OK:
		return generic_error(last_err,[])
	return true
static func import_inputmap_from_file(pFilePath : String, pMode : int):
	var last_err
	var curr_config = []
	var loaded_config = []
	var config = ConfigFile.new()
	
	if !get_filebased_current_project_inputmap(curr_config):
		return false
	if !get_inputmap_from_file(pFilePath,loaded_config):
		return false
	if !merge_inputmaps_by_mode(curr_config,loaded_config, pMode):
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
