extends Control
class_name ChoiceTooltipPopup

## Themeable tooltip for level-up choices. Does not block mouse input (mouse_filter_ignore).
## Instance this in the level-up panel and call set_content() + show_under_rect().

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var affinity_label: Label = $Panel/Margin/VBox/Affinity
@onready var tags_label: Label = $Panel/Margin/VBox/Tags
@onready var desc_label: Label = $Panel/Margin/VBox/Desc


func _ready() -> void:
	visible = false
	# Do not swallow input — let clicks reach the buttons underneath
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_children_mouse_filter(self, Control.MOUSE_FILTER_IGNORE)


func _set_children_mouse_filter(node: Node, filter: Control.MouseFilter) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = filter
			_set_children_mouse_filter(child, filter)


func set_content(title: String, affinity: String, tags: String, desc: String) -> void:
	if title_label:
		title_label.text = title
	if affinity_label:
		affinity_label.text = "Affinity: %s" % affinity
	if tags_label:
		tags_label.text = "Tags: %s" % tags
	if desc_label:
		desc_label.text = desc


func show_tooltip() -> void:
	visible = true


func hide_tooltip() -> void:
	visible = false
