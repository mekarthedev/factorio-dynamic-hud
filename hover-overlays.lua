require "commons"
require "events-dispatch"
require "core"

local hover_overlay_thickness = 4

events_dispatch:on_internal("player_setup", function (player_index)
    local player = game.get_player(player_index)

    if not player.gui.screen[own"top_hover"] then
        local top_hover = player.gui.screen.add{
            type = "flow",
            direction = "horizontal",
            name = own"top_hover"
        }
        top_hover.style.height = hover_overlay_thickness
        top_hover.style.horizontal_align = "center"

        local mod_gui_hover = top_hover.add{
            type = "empty-widget",
            name = "mod_gui_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = "mods_top_event"}
        }
        mod_gui_hover.style.horizontally_stretchable = true
        mod_gui_hover.style.vertically_stretchable = true

        local all_ui_hover = top_hover.add{
            type = "empty-widget",
            name = "all_ui_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = "all_ui_event"}
        }
        all_ui_hover.style.horizontally_stretchable = true
        all_ui_hover.style.vertically_stretchable = true

        local research_hover = top_hover.add{
            type = "empty-widget",
            name = "research_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = {"research_event", "side_menu_event", "map_options_event"}}
        }
        research_hover.style.horizontally_stretchable = true
        research_hover.style.vertically_stretchable = true
    end

    if not player.gui.screen[own"bottom_hover"] then
        local bottom_hover = player.gui.screen.add{
            type = "flow",
            direction = "horizontal",
            name = own"bottom_hover"
        }
        bottom_hover.style.height = hover_overlay_thickness
        bottom_hover.style.horizontal_align = "center"

        local toolbar_hover = bottom_hover.add{
            type = "empty-widget",
            name = "toolbar_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = "toolbar_event"}
        }
        toolbar_hover.style.horizontally_stretchable = true
        toolbar_hover.style.vertically_stretchable = true

        local quickbar_hover = bottom_hover.add{
            type = "empty-widget",
            name = "quickbar_hover",
            style= own"quickbar_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = "quickbar_event"}
        }
        quickbar_hover.style.vertically_stretchable = true

        local shortcuts_hover = bottom_hover.add{
            type = "empty-widget",
            name = "shortcuts_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = "shortcuts_event"}
        }
        shortcuts_hover.style.horizontally_stretchable = true
        shortcuts_hover.style.vertically_stretchable = true
    end

    if not player.gui.screen[own"left_hover"] then
        local left_hover = player.gui.screen.add{
            type = "empty-widget",
            name = own"left_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = {"surface_list_event", "mods_left_event"}}
        }
        left_hover.style.width = hover_overlay_thickness
    end

    if not player.gui.screen[own"right_hover"] then
        local right_hover = player.gui.screen.add{
            type = "empty-widget",
            name = own"right_hover",
            raise_hover_events = true,
            tags = {[own"on_hover"] = {"minimap_event", "map_options_event"}}
        }
        right_hover.style.width = hover_overlay_thickness
    end
end)

events_dispatch:on_event(defines.events.on_gui_hover, function(event)
    local hud_update_reason = event.element.tags[own"on_hover"]
    if not hud_update_reason then return end

    -- "on hover" should be renamed to "on enter", no throttling needed.
    local state = storage.per_player[event.player_index]
    if type(hud_update_reason) == "string" then
        state.time_of[hud_update_reason] = event.tick
    else
        for _, reason in pairs(hud_update_reason) do
            state.time_of[reason] = event.tick
        end
    end
    update_hud(event.player_index)
end)

function sync.hover_overlays_location(_, player)
    -- (Factorio v2.0.76) Don't place elements at {0,0}.
    -- See https://forums.factorio.com/viewtopic.php?t=133488

    local top_hover = player.gui.screen[own"top_hover"]
    top_hover.location = { 1, 0 }
    top_hover.style.width = player.display_resolution.width / player.display_scale

    local bottom_hover = player.gui.screen[own"bottom_hover"]
    bottom_hover.location = { 0, player.display_resolution.height - hover_overlay_thickness * player.display_scale }
    bottom_hover.style.width = player.display_resolution.width / player.display_scale

    local left_hover = player.gui.screen[own"left_hover"]
    left_hover.location = { 0, 1 }
    left_hover.style.height = player.display_resolution.height / player.display_scale

    local right_hover = player.gui.screen[own"right_hover"]
    right_hover.location = { player.display_resolution.width - hover_overlay_thickness * player.display_scale, 0 }
    right_hover.style.height = player.display_resolution.height / player.display_scale
end

events_dispatch:on_event(defines.events.on_player_display_resolution_changed, function(event)
    sync.hover_overlays_location(nil, game.get_player(event.player_index))
end)

events_dispatch:on_event(defines.events.on_player_display_scale_changed, function(event)
    sync.hover_overlays_location(nil, game.get_player(event.player_index))
end)
