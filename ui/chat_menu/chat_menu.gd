extends CanvasLayer

var is_blocked: bool = false
var is_moving_window: bool = false
var is_resizing_window: bool = false

@onready var body: TextureRect = %Texture

func toggle_visibility() -> void:
	visible = not visible

func toggle_move_window() -> void:
	is_moving_window = not is_moving_window

func toggle_resize_window() -> void:
	is_resizing_window = not is_resizing_window

func move_window() -> void:
	if not visible: return
	var mouse_pos: Vector2 = DisplayServer.mouse_get_position()
	body.position = mouse_pos

func resize_window() -> void:
	if not visible: return
	var mouse_pos: Vector2 = DisplayServer.mouse_get_position()
	var body_center_pos: Vector2 = body.position
	body.size = abs(body_center_pos - mouse_pos) * 2

func focus_chat() -> void:
	if not visible: return
	%ChatInput.grab_focus()

func _process(_delta: float) -> void:
	if is_moving_window: move_window()
	if is_resizing_window: resize_window()

func connect_signal() -> void:
	ChatManager.connect(&"update_local_chat_ui", update_chat)
	ChatManager.connect(&"remove_previous_message", remove_previous_message)

func update_chat(new_messages: Array[Dictionary]) -> void:
	for message: Dictionary in new_messages:
		add_message(message)

func remove_previous_message() -> void:
	%ChatText.text = ""
	update_chat(ChatManager.chat_history)

const NO_TIMESTAMP_CHANNELS: PackedStringArray = ["shell_input", "shell_error", "shell_output"]

func bbtext(value: Variant) -> String:
	return str(value).replace("[", "[lb]").replace("]", "[rb]")

func sender_color_html(sender_sid: Variant) -> String:
	var sid: int = int(sender_sid)
	if SessionManager.data.has(sid):
		var c: Variant = SessionManager.data[sid].get("color")
		if c is Color: return c.to_html(false)
	return "ffffff"

func add_message(message: Dictionary) -> void:
	var readable_sid: String = SessionManager.encode_session_id(message.get("sender_sid"))
	if not NetworkManager.is_online: readable_sid = "#OFFLINE"
	if not message.get("channel") in NO_TIMESTAMP_CHANNELS:
		%ChatText.text += str(message.get("timestamp")) + " "
	if message.get("channel") == "peer":
		MasterManager.play_server_sound(MasterManager.sounds.get_node(^"PlayerChat"))
		%ChatText.text += "[color=#" + sender_color_html(message.get("sender_sid")) + "]"
		%ChatText.text += bbtext(message.get("sender_name"))
		%ChatText.text += "(" + readable_sid + ")[/color]: "
		%ChatText.text += bbtext(message.get("text")) + "\n"
		await get_tree().process_frame
		%ChatText.scroll_to_line(%ChatText.get_line_count() - 1)
		return
	elif message.get("channel") == "shell_input":
		%ChatText.text += ":: "
	elif message.get("channel") == "shell_output":
		%ChatText.text += "/: "
	elif message.get("channel") == "shell_error":
		%ChatText.text += "E: "
	elif message.get("channel") == "admin":
		%ChatText.text += "ADMIN: "
	elif message.get("channel") == "target":
		%ChatText.text += "!!!: "
	elif message.get("channel") == "global":
		%ChatText.text += "***: "
	%ChatText.text += bbtext(message.get("text")) + "\n"
	await get_tree().process_frame
	%ChatText.scroll_to_line(%ChatText.get_line_count() - 1)

func _on_chat_input_text_submitted(raw: String) -> void:
	%ChatInput.clear()
	%ChatInput.release_focus()
	if raw.begins_with("/"): ConsoleManager.execute_raw_string(raw)
	else: ChatManager.send_message(raw, "peer", 0)

func set_font_size(value: int) -> void:
	%ChatText.add_theme_font_size_override(&"normal_font_size", value)
	%Header.add_theme_font_size_override(&"font_size", value)
	%ChatInput.add_theme_font_size_override(&"font_size", value)

func _on_chat_input_focus_entered() -> void:
	is_blocked = true

func _on_chat_input_focus_exited() -> void:
	is_blocked = false
