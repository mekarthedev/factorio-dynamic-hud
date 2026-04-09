require("own")

local hud_update_delay = 4 * 60

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
    local show_all = not state.dynamic_hud_enabled or state.inventory_open
    local show_inventory_related = show_all or state.inventory_closed_at ~= nil

    player.game_view_settings.show_research_info = show_all
    player.game_view_settings.show_side_menu = show_all
    player.game_view_settings.show_surface_list = show_all
    player.gui.top.visible = show_all

    -- show_controller_gui makes mouse cursor incorrectly indicate selected tool (e.g. wire).
    -- Instead hide each bar separately
    player.game_view_settings.show_tool_bar = show_inventory_related
    -- note: hiding the quickbar disables quickbar hotkeys for some reason
    player.game_view_settings.show_quickbar = show_inventory_related
    player.game_view_settings.show_shortcut_bar = show_inventory_related

    if state.inventory_closed_at ~= nil then
        -- its "nth" tick from 0, not from the moment of subscription
        -- so making checks more frequent
        -- to make the actual delay closer to the ideal delay
        local ticks_per_update = math.ceil(hud_update_delay / 4)
        script.on_nth_tick(ticks_per_update, function(event)
            local more_updates = false

            for player_index, state in pairs(storage.per_player) do
                if state.inventory_closed_at ~= nil then
                    if event.tick - state.inventory_closed_at >= hud_update_delay then
                        state.inventory_closed_at = nil
                        update_hud(state, game.get_player(player_index))
                    else
                        more_updates = true
                    end
                end
            end

            if not more_updates then
                script.on_nth_tick(ticks_per_update, nil)
            end
        end)
    end
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
        state.inventory_closed_at = event.tick
        update_hud(state, player)
    end
end)
