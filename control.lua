require("commons")

-- #todo: also show quckbar when opening a vehicle
-- #todo: show weapon bar during battle
-- #todo: show shortcut bar when wire cursor is selected
-- #todo: better onboarding message
-- #todo: test in multiplayer
-- #todo: settings for non-standard or opinionated cases (like minimap)
-- #todo: check if other gui roots should be hidden, aside from `top`

local hud_update_delay = 4 * 60

local function update_hud(player_index)
    local state = storage.per_player[player_index]
    local player = game.get_player(player_index)

    local show_all = not state.dynamic_hud_enabled or state.inventory_open
    local show_tools = show_all or state.time_of.inventory_closed ~= nil
    local show_research = show_all or state.time_of.research_updated ~= nil

    player.game_view_settings.show_side_menu = show_all
    player.game_view_settings.show_surface_list = show_all
    player.gui.top.visible = show_all

    player.game_view_settings.show_research_info = show_research

    -- show_controller_gui makes mouse cursor incorrectly indicate selected tool (e.g. wire).
    -- Instead hide each bar separately
    player.game_view_settings.show_tool_bar = show_tools
    -- note: hiding the quickbar disables quickbar hotkeys for some reason
    player.game_view_settings.show_quickbar = show_tools
    player.game_view_settings.show_shortcut_bar = show_tools

    if next(state.time_of) ~= nil then
        -- its "nth" tick from 0, not from the moment of subscription
        -- so making checks more frequent
        -- to make the actual delay closer to the ideal delay
        local ticks_per_update = math.ceil(hud_update_delay / 4)
        script.on_nth_tick(ticks_per_update, function(e)
            local wait_more = false

            for player_index, state in pairs(storage.per_player) do
                local update = false
                for event, tick in pairs(state.time_of) do
                    if e.tick - tick >= hud_update_delay then
                        state.time_of[event] = nil
                        update = true
                    else
                        wait_more = true
                    end
                end
                if update then
                    update_hud(player_index)
                end
            end

            if not wait_more then
                script.on_nth_tick(ticks_per_update, nil)
            end
        end)
    end
end

local function setup(player_index)
    local function add_state(state, key, initial_value)
        if state[key] == nil then
            state[key] = initial_value
        end
    end

    if not storage.per_player then
        storage.per_player = {}
    end
    if not storage.per_player[player_index] then
        storage.per_player[player_index] = {}
    end
    local state = storage.per_player[player_index]

    if state.dynamic_hud_enabled == nil then
        state.dynamic_hud_enabled = true
        game.get_player(player_index)
            .print("Your HUD will hide when not needed")
    end

    -- NOTE:
    -- after mod is published, presence of some keys
    -- does not indicate presence of other keys.
    -- Always use `add_state()` for new keys,
    -- `dynamic_hud_enabled` is the only exception.
    add_state(state, "inventory_open", false)
    add_state(state, "time_of", {})

    -- It is forbidden to update storage during `on_load`,
    -- and `on_configuration_changed` isn't affected by changes in `control.lua`,
    -- only by a change in the mod version.
    --
    -- So, when in development, a `own"activate"` have to be used
    -- to re-run setup after adding a new state key.
    --
    -- For that reason make sure `setup` is always idempotent.

    update_hud(player_index)
end

script.on_init(function()
    subscriptions:subscribe_all()
end)

script.on_load(function()
    if some(storage.per_player,
        function(state) return state.dynamic_hud_enabled end)
    then
        subscriptions:subscribe_all()
    end
end)

script.on_configuration_changed(function(event)
    for _, player in pairs(game.players) do
        setup(player.index)
    end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    setup(event.player_index)
end)

script.on_event(own"activate", function(event)
    local state = storage.per_player[event.player_index]
    state.dynamic_hud_enabled = not state.dynamic_hud_enabled
    -- for ease of mod development, re-run `setup` here instead of `update_hud`
    -- see `setup()` for details
    setup(event.player_index)

    if state.dynamic_hud_enabled then
        subscriptions:subscribe_all()

    elseif every(storage.per_player,
        function(state) return not state.dynamic_hud_enabled end)
    then
        subscriptions:unsubscribe_all()
    end
end)

-- The system UI elements somehow aren't affected
-- while the new game cutscene is playing
subscriptions:on_event(defines.events.on_cutscene_cancelled, function(event)
    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_cutscene_finished, function(event)
    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_gui_opened, function(event)
    if event.gui_type ~= defines.gui_type.controller then return end

    local state = storage.per_player[event.player_index]
    state.inventory_open = true
    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_gui_closed, function(event)
    if event.gui_type ~= defines.gui_type.controller then return end

    local state = storage.per_player[event.player_index]
    state.inventory_open = false
    state.time_of.inventory_closed = event.tick
    update_hud(event.player_index)
end)

local function on_active_research_updated(tick, force)
    for _, player in pairs(force.players) do
        local state = storage.per_player[player.index]
        state.time_of.research_updated = tick
        update_hud(player.index)
    end
end

subscriptions:on_event(defines.events.on_research_started, function(event)
    on_active_research_updated(event.tick, event.research.force)
end)

subscriptions:on_event(defines.events.on_research_finished, function(event)
    on_active_research_updated(event.tick, event.research.force)
end)

subscriptions:on_event(defines.events.on_research_cancelled, function(event)
    -- the goal is to update HUD only if the queue head was cancelled
    -- if queue is still not empty then `started` would fire for next tech
    if #event.force.research_queue == 0 then
        log("queue is empty")
        on_active_research_updated(event.tick, event.force)
    end
end)
