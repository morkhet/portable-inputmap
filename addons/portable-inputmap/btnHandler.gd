tool
extends VBoxContainer
	
func _ready():
	$optMode.items = []
	$optMode.add_item("OVERRIDE")
	$optMode.add_item("ONLY NEW")
	$optMode.add_item("BREAK ON ERROR")
func _on_btnImport_pressed():
	$btnImport/fdImport.popup_centered(Vector2(200,400))

func _on_btnExport_pressed():
	$btnExport/fdExport.popup_centered(Vector2(200,400))

func _on_fdImport_file_selected(path):
	if load("res://addons/portable-inputmap/portable-inputmap.gd").import_button_click(path,$optMode.selected):
		$lblStatus.text = "Status: Import completed. Please reload the project via Project->Reload Current Project"
	else:
		$lblStatus.text = "Status: Import failed. Check the output for further details."
func _on_fdExport_file_selected(path):
	if load("res://addons/portable-inputmap/portable-inputmap.gd").export_button_click(path):
		$lblStatus.text = "Status: export completed."
	else:
		$lblStatus.text = "Status: Export failed. Check the output for further details."
