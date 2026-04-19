require("commons")

-- #todo: allow other mods to define when they are allowed to be hidden
--        - StatsGui uses gui.screen to show stats similar to ups
--        - TaskList shows list of tasks in "keep open" mode
-- #todo: test in multiplayer

-- The "nth tick" counts from 0, not from the moment of subscribing to the event
-- More frequent checks mean having measured time intervals closer to ideal time intervals
local hud_check_period = ticks_per_second / 2

local driving_mode = {
    not_driving = 0,
    by_character = 1,
    by_player = 2,  -- remote driving
}

-- Put functions reading current game state here.
-- `function sync.some_data(state, player)`
-- No need to try to sync `time_of`. It will be cleared after re-sync.
-- `entity_related_players` will be cleared before global re-sync.
local sync = {}

local function sync_state(player_index)
    local state = storage.per_player[player_index]
    local player = game.get_player(player_index)

    for _, sync_part in pairs(sync) do
        sync_part(state, player)
    end

    state.time_of = {}
end

local function update_hud(player_index)
    local state = storage.per_player[player_index]
    local player = game.get_player(player_index)

    if state.settings.hud_update_delay == 0 then
        for event in pairs(state.time_of) do
            state.time_of[event] = nil
        end
    end

    -- Note: Other mods might forget to properly clear `player.opened` when closing their UIs.
    --   In that case, as of Factorio v2.0.76, `on_gui_closed` doesn't fire.
    --   Cannot rely on gui_type.custom to control HUD state, as a result.

    local show_all = not state.dynamic_hud_enabled
        or state.opened_gui == defines.gui_type.controller
        or state.time_of.inventory_closed ~= nil

    local show_research = show_all
        or state.time_of.research_updated ~= nil
    local show_side_menu = show_all
        or state.opened_gui == defines.gui_type.logistic
        or state.opened_gui == defines.gui_type.production
        or state.opened_gui == defines.gui_type.trains
        or state.opened_gui == defines.gui_type.achievement
        or state.opened_gui == defines.gui_type.bonus
    local show_minimap = show_all
        or (state.driving_mode ~= driving_mode.not_driving and state.settings.show_minimap_while_driving)
        or not state.settings.hide_minimap

    local show_map_options = show_all
        or state.time_of.controller_changed ~= nil
    local show_surface_list = show_all
        or state.time_of.controller_changed ~= nil
        or state.time_of.surface_changed ~= nil

    local show_controller_bars = show_all
        or state.opened_gui == defines.gui_type.item
        or state.opened_gui == defines.gui_type.entity
        or state.opened_gui == defines.gui_type.equipment
        or state.opened_gui == defines.gui_type.other_player
        or state.opened_gui == defines.gui_type.blueprint_library

    local in_combat = 
        state.time_of.involved_in_combat ~= nil
        or state.in_cursor == "combat"  -- #todo: use int enum
        or state.time_of.combat_cursor_dropped ~= nil

    local show_toolbar = show_controller_bars
        or state.time_of.toolbar_updated ~= nil
        or in_combat
        -- Workaround (Factorio v2.0.76):
        -- The vehicle toolbar is not affected by `show_tool_bar` while driving with a character
        -- but is affected while driving remotely. If hidden in remote, it will not show back up
        -- for vehicle driven by character until next `show_tool_bar = true` write.
        -- For that reason and to avoid flickering due to `shoot-enemy` action,
        -- lets just show character's toolbar along with vehicle's one.
        or state.driving_mode == driving_mode.by_character

    local show_quickbar = show_controller_bars
        or state.time_of.quickbar_updated ~= nil
        or not state.settings.hide_quickbar
        or (in_combat and state.settings.show_quickbar_in_combat)

    local show_shortcuts = show_controller_bars
        or state.in_cursor == "wire"
        or state.time_of.wire_cursor_dropped ~= nil

    local show_mod_top = show_all or not state.settings.hide_top
    local show_mod_left = show_all or not state.settings.hide_left
    local show_goal = show_all or not state.settings.hide_goal

    player.game_view_settings.show_research_info = show_research
    player.game_view_settings.show_side_menu = show_side_menu
    player.game_view_settings.show_map_view_options = show_map_options
    player.game_view_settings.show_minimap = show_minimap
    player.game_view_settings.show_surface_list = show_surface_list

    player.gui.top.visible = show_mod_top
    player.gui.left.visible = show_mod_left
    -- as of Factorio v2.0.76, goal.visible doesn't work, goal cannot be hidden
    player.gui.goal.visible = show_goal
    -- Note: gui.relative is already all about temporary ui elements

    -- show_controller_gui makes mouse cursor incorrectly indicate selected stack (e.g. wire).
    player.game_view_settings.show_tool_bar = show_toolbar
    -- note: hiding the quickbar disables quickbar hotkeys for some reason
    player.game_view_settings.show_quickbar = show_quickbar
    player.game_view_settings.show_shortcut_bar = show_shortcuts

    if next(state.time_of) ~= nil then
        script.on_nth_tick(hud_check_period, function(e)
            local wait_more = false

            for player_index, state in pairs(storage.per_player) do
                local update = false
                for event, tick in pairs(state.time_of) do
                    if e.tick - tick >= state.settings.hud_update_delay then
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
                script.on_nth_tick(hud_check_period, nil)
            end
        end)
    end
end

-- a convenience function for a common usecase
local function update_hud_bacause(event_name, player_index, tick)
    local state = storage.per_player[player_index]
    state.time_of[event_name] = tick
    update_hud(player_index)
end

local function setup(player_index)
    -- Note:
    -- After mod is published, presence of some keys
    -- does not indicate presence of other keys.
    -- Always use `set_default()` to add new keys,
    -- `dynamic_hud_enabled` should be the only exception.

    -- Note:
    -- It is forbidden to update storage during `on_load`,
    -- and `on_configuration_changed` isn't affected by changes in `control.lua`,
    -- only by a change in the mod version.
    --
    -- So, when in development, `own"activate"` have to be used
    -- to re-run setup after adding a new state key.
    --
    -- For that reason make sure `setup` is always idempotent.

    set_default(storage, "per_player", {})
    set_default(storage, "entity_related_players", {})

    local state = set_default(storage.per_player, player_index, {})

    if state.dynamic_hud_enabled == nil then
        state.dynamic_hud_enabled = true
        game.get_player(player_index).print({"welcome-message"})
    end

    set_default(state, "settings", {})
    local ps = settings.get_player_settings(player_index)
    state.settings.hud_update_delay = ps[own"delay"].value * ticks_per_second
    state.settings.hide_minimap = ps[own"hide-minimap"].value
    state.settings.show_minimap_while_driving = ps[own"show-minimap-while-driving"].value
    state.settings.hide_quickbar = ps[own"hide-quickbar"].value
    state.settings.show_quickbar_in_combat = ps[own"show-quickbar-in-combat"].value
    state.settings.hide_top = ps[own"hide-top"].value
    state.settings.hide_left = ps[own"hide-left"].value
    state.settings.hide_goal = ps[own"hide-goal"].value

    set_default(state, "time_of", {})
    set_default(state, "driving_mode", driving_mode.not_driving)

    sync_state(player_index)
    update_hud(player_index)
end

local function setup_all()
    storage.entity_related_players = {}
    for _, player in pairs(game.players) do
        setup(player.index)
    end
end

--------

script.on_init(function()
    subscriptions:subscribe_all()
    -- most of "first launch" code should go to `on_configuration_changed`
end)

script.on_load(function()
    if some(storage.per_player, function(s) return s.dynamic_hud_enabled end) then
        subscriptions:subscribe_all()
    end
end)

script.on_configuration_changed(function(event)
    setup_all()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if not is_own(event.setting) then return end

    if event.setting_type == "runtime-per-user" and event.player_index ~= nil then
        setup(event.player_index)
    end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    setup(event.player_index)
end)

script.on_event(own"activate", function(event)
    local state = storage.per_player[event.player_index]
    state.dynamic_hud_enabled = not state.dynamic_hud_enabled

    if state.dynamic_hud_enabled then
        -- run `setup` instead of `update_hud` to synchronize state with possibly changed reality
        if not subscriptions.subscribed then
            subscriptions:subscribe_all()
            setup_all()
        else
            -- Technically this is not needed because as long as `subscriptions` is up
            -- every player has their state up-to-date regardless of their `dynamic_hud_enabled`.
            -- Might be helpful in development.
            setup(event.player_index)
        end

    else
        update_hud(event.player_index)

        if every(storage.per_player, function(s) return not s.dynamic_hud_enabled end) then
            subscriptions:unsubscribe_all()
        end
    end
end)

--------

-- The system UI elements somehow aren't affected
-- while the new game cutscene is playing
subscriptions:on_event(defines.events.on_cutscene_cancelled, function(event)
    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_cutscene_finished, function(event)
    update_hud(event.player_index)
end)

function sync.opened_gui(state, player)
    state.opened_gui = player.opened_gui_type
end

subscriptions:on_event(defines.events.on_gui_opened, function(event)
    local player = game.get_player(event.player_index)
    local state = storage.per_player[event.player_index]

    sync.opened_gui(state, player)

    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)
    local state = storage.per_player[event.player_index]

    sync.opened_gui(state, player)

    if event.gui_type == defines.gui_type.controller then
        state.time_of.inventory_closed = event.tick
    end

    update_hud(event.player_index)
end)

local function on_active_research_updated(tick, force)
    for _, player in pairs(force.players) do
        update_hud_bacause("research_updated", player.index, tick)
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
        on_active_research_updated(event.tick, event.force)
    end
end)

function sync.in_cursor(state, player)
    local cursor_stack = player.cursor_stack
    local in_cursor = nil
    if cursor_stack and cursor_stack.valid_for_read then
        if cursor_stack.name == "red-wire"
            or cursor_stack.name == "green-wire"
            or cursor_stack.name == "copper-wire"
        then
            in_cursor = "wire"

        elseif cursor_stack.prototype.group.name == "combat"
            or cursor_stack.prototype.capsule_action  -- e.g. fish is not in combat group
                and cursor_stack.name ~= "cliff-explosives"  -- not for combat
                and cursor_stack.name ~= "artillery-targeting-remote"  -- no direct involvment
        then
            in_cursor = "combat"
        end
    end
    state.in_cursor = in_cursor
end

subscriptions:on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local state = storage.per_player[event.player_index]
    local player = game.get_player(event.player_index)
    local in_cursor_before = state.in_cursor
    sync.in_cursor(state, player)

    if state.in_cursor ~= in_cursor_before then
        if state.in_cursor ~= "wire" and in_cursor_before == "wire" then
            state.time_of.wire_cursor_dropped = event.tick
        end
        if state.in_cursor ~= "combat" and in_cursor_before == "combat" then
            state.time_of.combat_cursor_dropped = event.tick
        end

        -- Note: cursor_stack_changed might be called frequently
        -- e.g. when building a belt by dragging.
        -- No need to re-update when there were no changes to cursor kind.
        update_hud(event.player_index)
    end
end)

subscriptions:on_event(own"next-weapon", function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

subscriptions:on_event(defines.events.on_player_armor_inventory_changed, function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

subscriptions:on_event(defines.events.on_player_gun_inventory_changed, function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

subscriptions:on_event(defines.events.on_player_ammo_inventory_changed, function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

subscriptions:on_event(own"shoot-enemy", function(event)
    local state = storage.per_player[event.player_index]
    state.time_of.involved_in_combat = event.tick
    state.time_of.toolbar_updated = event.tick
    update_hud(event.player_index)
end)

subscriptions:on_event(own"shoot-selected", function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

subscriptions:on_event(defines.events.on_entity_damaged, function(event)
    local attacker = event.cause or event.source  -- it is unclear if both can be nil at the same time
    local victim = event.entity

    -- Don't consider it "combat" when damaging or being damaged by environment
    -- (unless attacker and victim are from opposing forces, or are characters).
    -- Note: for some reason character is considered environment.
    if attacker and attacker.force.is_enemy(victim.force)
        or attacker and attacker.prototype.name == "character"
        or victim.prototype.name == "character"
        or attacker and attacker.prototype.group.name ~= "environment"
            and victim.prototype.group.name ~= "environment"
    then
        local attacker_player_index = attacker and player_index_of(attacker)
        if attacker_player_index then
            update_hud_bacause("involved_in_combat", attacker_player_index, event.tick)
        end

        local victim_player_index = player_index_of(victim)
        if victim_player_index then
            update_hud_bacause("involved_in_combat", victim_player_index, event.tick)
        end
    end
end)

function sync.driving_mode(state, player)
    if not player.driving or not player.vehicle then  -- it's uknown if vehicle can be nil when driving
        state.driving_mode = driving_mode.not_driving
    else
        if player.vehicle.get_driver().is_player() then
            state.driving_mode = driving_mode.by_player
        else
            state.driving_mode = driving_mode.by_character
        end

        local related_players = set_default(
            storage.entity_related_players, player.vehicle.unit_number, {}
        )
        related_players[player.index] = true
        script.register_on_object_destroyed(player.vehicle)
    end
end

subscriptions:on_event(defines.events.on_player_driving_changed_state, function(event)
    local state = storage.per_player[event.player_index]
    local player = game.get_player(event.player_index)

    sync.driving_mode(state, player)

    -- Just an optimization for memory use and amount of looping, doesn't affect logic.
    if state.driving_mode == driving_mode.not_driving and event.entity then
        local old_vehicle = event.entity
        local related_players = storage.entity_related_players[old_vehicle.unit_number]
        if related_players then
            related_players[event.player_index] = nil
            if next(related_players) == nil then
                storage.entity_related_players[old_vehicle.unit_number] = nil
            end
        end
    end

    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_object_destroyed, function(event)
    if event.type ~= defines.target_type.entity then return end
    local related_players = storage.entity_related_players[event.useful_id]
    if not related_players then return end

    for player_index in pairs(related_players) do
        sync.driving_mode(storage.per_player[player_index], game.get_player(player_index))
        update_hud(player_index)
    end
    storage.entity_related_players[event.useful_id] = nil
end)

subscriptions:on_event(defines.events.on_player_controller_changed, function(event)
    local state = storage.per_player[event.player_index]
    state.time_of.controller_changed = event.tick
    -- It is possible to sit into a vehicle and then remotely "enter" another vehicle.
    -- `on_player_driving_changed_state` won't fire when going back.
    sync.driving_mode(state, game.get_player(event.player_index))
    update_hud(event.player_index)
end)

subscriptions:on_event(defines.events.on_player_changed_surface, function(event)
    update_hud_bacause("surface_changed", event.player_index, event.tick)
end)

subscriptions:on_event(defines.events.on_player_set_quick_bar_slot, function(event)
    update_hud_bacause("quickbar_updated", event.player_index, event.tick)
end)
