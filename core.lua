require "commons"
require "events-dispatch"

-- The "nth tick" counts from 0, not from the moment of subscribing to the event.
-- More frequent checks mean having measured time intervals closer to ideal time intervals.
local hud_check_period = ticks_per_second / 2

alerts_check_period = 5 * ticks_per_second

-- In case hud update delay is set to 0, notification-type updates to UI still need to be indicated.
-- Configure meaningful minimum time to wait before dismissing notification-type updates to UI.
-- A "notification-type update to UI" is an event that directly imply some changes in related UI.
-- E.g. involved_in_combat doesn't imply that any hidden UI has changed.
-- Shooting on the other hand implies changes to the indicator of amount of ammo left.
local minimum_update_delay = {
    -- [keyof(state.time_of)] = integer ticks
    research_event = 2 * ticks_per_second,  -- finished research notification
    quickbar_event = 1 * ticks_per_second,  -- quickbars rotation notification
    toolbar_event = 1 * ticks_per_second,  -- changes in toolbar (including ammo reduction when shooting)
    all_ui_event = 1 * ticks_per_second,  -- ui scale changed

    -- Assume `time_of.alerts_event` is the tick of some previous check.
    -- Prevent "flickering" by making sure:
    -- - Visibility duration is larger than period between checks
    -- - Check happens at least 1 tick before hiding
    alerts_event = 1 + math.max(10 * ticks_per_second, alerts_check_period)
}

driving_mode = {
    not_driving = 0,
    by_character = 1,
    by_player = 2,  -- remote driving
}

cursor_type = {
    wire = 1,
    combat = 2,
}

default_throttle_threshold = 1 * ticks_per_second

-- Put functions reading current state of a player into `sync`.
-- `function sync.some_player_state(state, player)`
-- `sync` is guaranteed to run before `bind`.
-- `sync` is guaranteed to run over all players, not just connected.
-- No need to try to sync `time_of`.
-- `entity_related_players` will be cleared before total re-sync.
sync = {}
function sync_state(player_index)
    local state = storage.per_player[player_index]
    local player = game.get_player(player_index)
    for _, sync_part in pairs(sync) do
        sync_part(state, player)
    end
end

-- Put functions setting up subscriptions for game events here.
-- Otherwise, `on_load` might fail if client doesn't subscribe to the same set of events as server.
-- `function bind.something_eventful()`
-- `bind` is guaranteed to run after `sync`.
-- During binding, `game` is not available and `storage` is readonly. I.e. only `on_load`-safe code.
bind = {}
function update_event_bindings()
    for _, bind_part in pairs(bind) do
        bind_part()
    end
end

-- MARK: update_hud()
function update_hud(player_index)
    local state = storage.per_player[player_index]
    local time_of = state.time_of
    local settings = state.settings
    local player = game.get_player(player_index)

    if settings.hud_update_delay == 0 then
        for event in pairs(time_of) do
            if not minimum_update_delay[event] then
                time_of[event] = nil
            end
        end
    end

    -- Note: Other mods might forget to properly clear `player.opened` when closing their UIs.
    --   In that case, as of Factorio v2.0.76, `on_gui_closed` doesn't fire.
    --   Cannot rely on gui_type.custom to control HUD state, as a result.

    local show_all = not state.dynamic_hud_enabled
        or state.opened_gui == defines.gui_type.controller
        or time_of.inventory_closed ~= nil
        or time_of.all_ui_event ~= nil

    local show_research = show_all
        or time_of.research_event ~= nil
    local show_side_menu = show_all
        or time_of.side_menu_event ~= nil
        or state.opened_gui == defines.gui_type.logistic
        or state.opened_gui == defines.gui_type.production
        or state.opened_gui == defines.gui_type.trains
        or state.opened_gui == defines.gui_type.achievement
        or state.opened_gui == defines.gui_type.bonus
    local show_minimap = show_all
        or (state.driving_mode ~= driving_mode.not_driving and settings.show_minimap_while_driving)
        or time_of.minimap_event ~= nil
        or not settings.hide_minimap

    local show_map_options = show_all
        or time_of.controller_changed ~= nil
        or time_of.map_options_event ~= nil
    local show_surface_list = show_all
        or time_of.controller_changed ~= nil
        or time_of.surface_list_event ~= nil

    local show_alerts = show_all
        or time_of.alerts_event ~= nil
        or not settings.hide_alerts

    local show_controller_bars = show_all
        or state.opened_gui == defines.gui_type.item
        or state.opened_gui == defines.gui_type.entity
        or state.opened_gui == defines.gui_type.equipment
        or state.opened_gui == defines.gui_type.other_player
        or state.opened_gui == defines.gui_type.blueprint_library

    local in_combat = 
        time_of.involved_in_combat ~= nil
        or state.in_cursor == cursor_type.combat
        or time_of.combat_cursor_dropped ~= nil

    local show_toolbar = show_controller_bars
        or time_of.toolbar_event ~= nil
        or in_combat
        -- Workaround (Factorio v2.0.76, expected to be fixed in v2.1):
        -- The vehicle toolbar is not affected by `show_tool_bar` while driving with a character
        -- but is affected while driving remotely. If hidden in remote, it will not show back up
        -- for vehicle driven by character until next `show_tool_bar = true` write.
        -- For that reason and to avoid flickering due to `shoot-enemy` action,
        -- lets just show character's toolbar along with vehicle's one.
        or state.driving_mode == driving_mode.by_character

    local show_quickbar = show_controller_bars
        or time_of.quickbar_event ~= nil
        or not settings.hide_quickbar
        or (in_combat and settings.show_quickbar_in_combat)

    local show_shortcuts = show_controller_bars
        or state.in_cursor == cursor_type.wire
        or time_of.shortcuts_event ~= nil

    local show_mod_top = show_all
        or time_of.mods_top_event ~= nil
        or not settings.hide_top
    local show_mod_left = show_all
        or time_of.mods_left_event ~= nil
        or not settings.hide_left
    local show_goal = show_all
        or time_of.mods_left_event ~= nil  -- whatever while goal cannot be hidden
        or not settings.hide_goal

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
    -- note: hiding the quickbar disables quickbar hotkeys (expected to be fixed in Factorio 2.1)
    player.game_view_settings.show_quickbar = show_quickbar
    player.game_view_settings.show_shortcut_bar = show_shortcuts
    player.game_view_settings.show_alert_gui = show_alerts

    if next(time_of) ~= nil then
        schedule_hud_update()
    end
end

function bind.scheduled_hud_updates()
    if some(storage.per_player, function(s) return next(s.time_of) ~= nil end) then
        schedule_hud_update()
    end
end

local scheduled_update
function schedule_hud_update()
    if scheduled_update then return end

    scheduled_update = events_dispatch:on_nth_tick(hud_check_period, function(e)
        local wait_more = false

        for player_index, state in pairs(storage.per_player) do
            local update = false
            for event, tick in pairs(state.time_of) do
                local update_delay = math.max(state.settings.hud_update_delay, minimum_update_delay[event] or 0)
                if e.tick - tick >= update_delay then
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
            events_dispatch:cancel(scheduled_update)
            scheduled_update = nil
        end
    end)
end

-- a convenience function for a common usecase
function update_hud_bacause(event_name, player_index, tick)
    local state = storage.per_player[player_index]
    state.time_of[event_name] = tick
    update_hud(player_index)
end

-- MARK: Players setup

function setup(player_index)
    -- Note:
    -- After mod is published, presence of some keys
    -- does not indicate presence of other keys.
    -- Always use `set_default()` to add new keys,
    -- `dynamic_hud_enabled` should be the only exception.

    local state = set_default(storage.per_player, player_index, {})

    if state.dynamic_hud_enabled == nil then
        state.dynamic_hud_enabled = true
        game.get_player(player_index).print({"welcome-message"})
    end

    set_default(state, "settings", {})
    set_default(state, "time_of", {})
    set_default(state, "driving_mode", driving_mode.not_driving)
    set_default(state, "alerts_summary", {})

    events_dispatch:notify("internal", "player_setup", player_index)
end

function remove(player_index)
    storage.per_player[player_index] = nil
    for unit_number, related_players in pairs(storage.entity_related_players) do
        related_players[player_index] = nil
        if next(related_players) == nil then
            storage.entity_related_players[unit_number] = nil
        end
    end
end

function update(player_index)
    local state = storage.per_player[player_index]

    -- Not placing in `sync` to guarantee that settings are read before any other `sync`.
    local ps = settings.get_player_settings(player_index)
    state.settings.hud_update_delay = ps[own"delay"].value * ticks_per_second
    state.settings.hide_minimap = ps[own"hide-minimap"].value
    state.settings.show_minimap_while_driving = ps[own"show-minimap-while-driving"].value
    state.settings.hide_quickbar = ps[own"hide-quickbar"].value
    state.settings.quickbar_workaround_enabled = ps[own"quickbar-workaround-enabled"].value
    state.settings.show_quickbar_on_use = ps[own"show-quickbar-on-use"].value
    state.settings.show_quickbar_in_combat = ps[own"show-quickbar-in-combat"].value
    state.settings.hide_alerts = ps[own"hide-alerts"].value
    state.settings.hide_top = ps[own"hide-top"].value
    state.settings.hide_left = ps[own"hide-left"].value
    state.settings.hide_goal = ps[own"hide-goal"].value

    sync_state(player_index)
    update_hud(player_index)
end

function init()
    -- Note:
    -- It is forbidden to update storage during `on_load`,
    -- and `on_configuration_changed` isn't affected by changes in `control.lua`,
    -- only by a change in the mod version.
    --
    -- So, when in development, `own"activate"` have to be used
    -- to re-run init after adding a new storage/state keys.
    --
    -- For that reason make sure `init` is always idempotent.

    set_default(storage, "per_player", {})
    events_dispatch:use_storage(set_default(storage, "events_dispatch", {}))
    set_default(storage, "throttle", {})
    set_default(storage.throttle, "check_alerts", {})  -- per force
    set_default(storage.throttle, "involved_in_combat", {})  -- per player
    storage.version = script.active_mods[script.mod_name]

    -- Remove state of removed players
    storage.entity_related_players = {}  -- reset anything cached
    local players = game.players
    for player_index in pairs(storage.per_player) do
        if not players[player_index] then
            remove(player_index)
        end
    end
    -- Setup new players if any.
    for _, player in pairs(players) do
        setup(player.index)
        update(player.index)
    end

    update_event_bindings()
end
