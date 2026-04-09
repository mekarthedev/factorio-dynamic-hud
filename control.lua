require("own")

local function storage_per_player(player_index)
  if not storage.per_player then
    storage.per_player = {}
  end
  if not storage.per_player[player_index] then
    storage.per_player[player_index] = {}
  end
  return storage.per_player[player_index]
end

local function update_hud(state, player)
    local show = state.inventory_open or not state.dynamic_hud_enabled

    player.game_view_settings.show_research_info = show
    player.game_view_settings.show_side_menu = show
    player.game_view_settings.show_surface_list = show
    player.gui.top.visible = show

    -- show_controller_gui stops displaying mouse cursor in a correct state.
    -- Instead hide each bar separately
    player.game_view_settings.show_tool_bar = show
    -- hiding the quickbar disables quickbar hotkeys
    player.game_view_settings.show_quickbar = show
    player.game_view_settings.show_shortcut_bar = show
end

local function setup(player)
    local state = storage_per_player(player.index)
    if state.dynamic_hud_enabled == nil then
        state.dynamic_hud_enabled = true
        state.inventory_open = false
        update_hud(state, player)
        player.print("Your HUD will hide when not needed")
    end
end

script.on_init(function(event)
    for _, player in pairs(game.players) do
        setup(player)
    end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    setup(player)
end)

script.on_event(own"activate", function(event)
    local player = game.get_player(event.player_index)
    local state = storage_per_player(event.player_index)

    state.dynamic_hud_enabled = not state.dynamic_hud_enabled
    update_hud(state, player)
end)

script.on_event(defines.events.on_gui_opened, function(event)
    if event.gui_type ~= defines.gui_type.controller then return end

    local player = game.get_player(event.player_index)
    local state = storage_per_player(event.player_index)

    state.inventory_open = true
    if state.dynamic_hud_enabled then
        update_hud(state, player)
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    if event.gui_type ~= defines.gui_type.controller then return end

    local player = game.get_player(event.player_index)
    local state = storage_per_player(event.player_index)

    state.inventory_open = false
    if state.dynamic_hud_enabled then
        update_hud(state, player)
    end
end)
