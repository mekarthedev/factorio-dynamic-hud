require "commons"

local gui_styles = data.raw["gui-style"].default
local quickbar_style = gui_styles["quick_bar_slot_window_frame"]
gui_styles[own"quickbar_hover"] = {
    type = "empty_widget_style",
    parent = "empty_widget",
    minimal_width = quickbar_style.minimal_width or 936,
}
