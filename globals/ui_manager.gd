extends Control

const LOBBY_FILE: String = "res://ui/lobby/lobby.tscn"
const PAUSE_MENU_FILE: String = "res://ui/pause_menu/pause_menu.tscn"
const CHAT_MENU_FILE: String = "res://ui/chat_menu/chat_menu.tscn"
var lobby_node: CanvasLayer = null
var pause_menu_node: CanvasLayer = null
var chat_menu_node: CanvasLayer = null

var is_ui_configured: bool = false

func update_lobby_register() -> void:
	if not is_ui_configured: return
	lobby_node.update_lobby_register()

func update_online_status() -> void:
	if not is_ui_configured: return
	lobby_node.update_online_status()

## global handler for making line inputs unfocus when clicking outside them
func _input(event: InputEvent) -> void:
	if not is_ui_configured: return
	if not event is InputEventMouseButton and not event.is_action_pressed(&"UnfocusChat"): return
	if not event.is_pressed(): return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT: return
	var focused_node: Control = get_viewport().gui_get_focus_owner()
	if focused_node == null: return
	var mouse_pos: Vector2 = focused_node.get_global_mouse_position()
	var control_rect := Rect2(Vector2.ZERO, focused_node.size)
	if control_rect.has_point(mouse_pos): return
	focused_node.release_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not is_ui_configured: return # could work for dedicated server console as well so idk
	if event.is_action_pressed(&"FocusChat"):
		chat_menu_node.focus_chat()
	if event.is_action_pressed(&"Pause"):
		if lobby_node.visible and IngameManager.current_state == IngameManager.State.STOPPED: return
		if not SessionManager.is_op(multiplayer.get_unique_id()): return
		MasterManager.set_pause.rpc_id(1, not pause_menu_node.visible)
	if event.is_action_pressed(&"MoveWindow"):
		chat_menu_node.toggle_move_window()
	if event.is_action_pressed(&"ResizeWindow"):
		chat_menu_node.toggle_resize_window()
	if event.is_action_pressed(&"ToggleLobby"):
		lobby_node.activate(not lobby_node.visible)
	if event.is_action_pressed(&"HideChat"):
		chat_menu_node.toggle_visibility()
		return
	if event is InputEventKey and event.physical_keycode == KEY_TAB and not event.echo:
		if get_viewport().gui_get_focus_owner() != null: return
		toggle_leaderboard(event.is_pressed())

func master_enter_tree() -> void:
	if NetworkManager.is_dedicated_server:
		ConsoleManager.initialize_dedicated_server_console()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	initialize_ui()
	is_ui_configured = true

func initialize_ui() -> void:
	create_lobby()
	lobby_node.activate(true)
	create_pause_menu()
	create_chat_menu()
	chat_menu_node.visible = false
	lobby_node.write_version_text()
	chat_menu_node.connect_signal()
	create_round_label()
	create_leaderboard()

## round indicator shown in the top-left corner during a match
var round_label: Label = null

func create_round_label() -> void:
	if round_label != null: return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	round_label = Label.new()
	round_label.add_theme_font_size_override(&"font_size", 40)
	round_label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.75))
	round_label.position = Vector2(16, 10)
	round_label.visible = false
	layer.add_child(round_label)

func set_round_label(current_round: int) -> void:
	if round_label == null: return
	if current_round <= 0:
		round_label.visible = false
		return
	round_label.text = "ROUND " + str(current_round)
	round_label.visible = true

## Tab leaderboard: names/colors, kills/deaths, K/D, score and ping
var leaderboard_node: CanvasLayer = null
var leaderboard_grid: GridContainer = null
var leaderboard_refresh_clock: float = 0.0

func create_leaderboard() -> void:
	if leaderboard_node != null: return
	leaderboard_node = CanvasLayer.new()
	leaderboard_node.layer = 95
	leaderboard_node.visible = false
	add_child(leaderboard_node)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaderboard_node.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "LEADERBOARD"
	title.add_theme_font_size_override(&"font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	leaderboard_grid = GridContainer.new()
	leaderboard_grid.columns = 6
	leaderboard_grid.add_theme_constant_override(&"h_separation", 24)
	leaderboard_grid.add_theme_constant_override(&"v_separation", 4)
	vbox.add_child(leaderboard_grid)

func toggle_leaderboard(show: bool) -> void:
	if leaderboard_node == null: return
	leaderboard_node.visible = show
	if show:
		leaderboard_refresh_clock = 0.0

const LB_HEADERS: PackedStringArray = ["PLAYER", "KILLS", "DEATHS", "K/D", "SCORE", "PING"]
func refresh_leaderboard() -> void:
	if leaderboard_grid == null: return
	for child: Node in leaderboard_grid.get_children(): child.queue_free()
	for header: String in LB_HEADERS:
		leaderboard_grid.add_child(lb_cell(header, Color(1.0, 1.0, 1.0, 0.6), HORIZONTAL_ALIGNMENT_LEFT))
	var rows: Array[int] = []
	for sid: int in SessionManager.data.keys():
		if sid == 0: continue
		rows.append(sid)
	rows.sort_custom(func(a: int, b: int) -> bool:
		return SessionManager.data[a].get("score", 0) > SessionManager.data[b].get("score", 0))
	for sid: int in rows:
		var entry: Dictionary = SessionManager.data[sid]
		var color: Color = entry.get("color", Color.WHITE)
		var kills: int = entry.get("kills", 0)
		var deaths: int = entry.get("deaths", 0)
		var kd: String = "%.2f" % (float(kills) / max(1, deaths))
		var ping_text: String = "bot"
		if sid > 1: ping_text = str(entry.get("ping", 0)) + " ms"
		leaderboard_grid.add_child(lb_cell(str(entry.get("name", "?")), color, HORIZONTAL_ALIGNMENT_LEFT))
		leaderboard_grid.add_child(lb_cell(str(kills), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		leaderboard_grid.add_child(lb_cell(str(deaths), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		leaderboard_grid.add_child(lb_cell(kd, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		leaderboard_grid.add_child(lb_cell(str(entry.get("score", 0)), color, HORIZONTAL_ALIGNMENT_CENTER))
		leaderboard_grid.add_child(lb_cell(ping_text, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))

func lb_cell(text: String, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_font_size_override(&"font_size", 20)
	return label

func _process(delta: float) -> void:
	if not is_ui_configured: return
	if leaderboard_node == null or not leaderboard_node.visible: return
	leaderboard_refresh_clock -= delta
	if leaderboard_refresh_clock <= 0.0:
		leaderboard_refresh_clock = 1.0
		refresh_leaderboard()

func create_lobby() -> void:
	if lobby_node != null: return
	lobby_node = load(LOBBY_FILE).instantiate()
	add_child(lobby_node)

func create_pause_menu() -> void:
	if pause_menu_node != null: return
	pause_menu_node = load(PAUSE_MENU_FILE).instantiate()
	add_child(pause_menu_node)

func create_chat_menu() -> void:
	if chat_menu_node != null: return
	chat_menu_node = load(CHAT_MENU_FILE).instantiate()
	add_child(chat_menu_node)

func delete_lobby() -> void:
	if lobby_node == null: return
	lobby_node.queue_free()

func toggle_admin_options(is_admin: bool) -> void:
	if not is_ui_configured: return
	pause_menu_node.toggle_admin_options(is_admin)

@rpc("authority", "reliable")
func confirm_spectating() -> void:
	if lobby_node == null: return
	lobby_node.toggle_spectate_window(true)
