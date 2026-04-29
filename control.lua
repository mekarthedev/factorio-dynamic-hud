require("commons")

-- #todo: allow other mods to define when they are allowed to be hidden
--        - StatsGui uses gui.screen to show stats similar to ups
--        - TaskList shows list of tasks in "keep open" mode
-- #todo: test tips
-- #todo: upcoming in 2.1
--        - support show_pins_gui: https://forums.factorio.com/viewtopic.php?t=133423
--        - remove quckbar workaround: https://forums.factorio.com/viewtopic.php?t=133377
-- #todo: show custom short lived "no more alerts" alert as a replacement for built-in hiding when no alerts
-- #todo: pretty popup for welcome message instead of console

-- The "nth tick" counts from 0, not from the moment of subscribing to the event.
-- More frequent checks mean having measured time intervals closer to ideal time intervals.
local hud_check_period = ticks_per_second / 2

local alerts_check_period = 5 * ticks_per_second

-- In case hud update delay is set to 0, notification-type updates to UI still need to be indicated.
-- Configure meaningful minimum time to wait before dismissing notification-type updates to UI.
-- A "notification-type update to UI" is an event that directly imply some changes in related UI.
-- E.g. involved_in_combat doesn't imply that any hidden UI has changed.
-- Shooting on the other hand implies changes to the indicator of amount of ammo left.
local minimum_update_delay = {
    -- [keyof(state.time_of)] = integer ticks
    research_updated = 2 * ticks_per_second,  -- finished research notification
    quickbar_interaction = 1 * ticks_per_second,  -- quickbars rotation notification
    toolbar_updated = 1 * ticks_per_second,  -- changes in toolbar (including ammo reduction when shooting)
    ui_updated = 1 * ticks_per_second,  -- ui scale changed

    -- Assume `time_of.alerts_updated` is the tick of some previous check.
    -- Prevent "flickering" by making sure:
    -- - Visibility duration is larger than period between checks
    -- - Check happens at least 1 tick before hiding
    alerts_updated = 1 + math.max(10 * ticks_per_second, alerts_check_period)
}

local driving_mode = {
    not_driving = 0,
    by_character = 1,
    by_player = 2,  -- remote driving
}

local cursor_type = {
    wire = 1,
    combat = 2,
}

-- Put functions reading current state of a player into `sync`.
-- `function sync.some_player_state(state, player)`
-- `sync` is guaranteed to run before `bind`.
-- `sync` is guaranteed to run over all players, not just connected.
-- No need to try to sync `time_of`.
-- `entity_related_players` will be cleared before total re-sync.
local sync = {}
local function sync_state(player_index)
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
local bind = {}
local function update_event_bindings()
    for _, bind_part in pairs(bind) do
        bind_part()
    end
end

local update_hud, schedule_hud_update

-- MARK: update_hud()
function update_hud(player_index)
    local state = storage.per_player[player_index]
    local player = game.get_player(player_index)

    if state.settings.hud_update_delay == 0 then
        for event in pairs(state.time_of) do
            if not minimum_update_delay[event] then
                state.time_of[event] = nil
            end
        end
    end

    -- Note: Other mods might forget to properly clear `player.opened` when closing their UIs.
    --   In that case, as of Factorio v2.0.76, `on_gui_closed` doesn't fire.
    --   Cannot rely on gui_type.custom to control HUD state, as a result.

    local show_all = not state.dynamic_hud_enabled
        or state.opened_gui == defines.gui_type.controller
        or state.time_of.inventory_closed ~= nil
        or state.time_of.ui_updated ~= nil

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
        or state.time_of.minimap_updated ~= nil
        or not state.settings.hide_minimap

    local show_map_options = show_all
        or state.time_of.controller_changed ~= nil
    local show_surface_list = show_all
        or state.time_of.controller_changed ~= nil
        or state.time_of.surface_changed ~= nil

    local show_alerts = show_all
        or state.time_of.alerts_updated ~= nil
        or not state.settings.hide_alerts

    local show_controller_bars = show_all
        or state.opened_gui == defines.gui_type.item
        or state.opened_gui == defines.gui_type.entity
        or state.opened_gui == defines.gui_type.equipment
        or state.opened_gui == defines.gui_type.other_player
        or state.opened_gui == defines.gui_type.blueprint_library

    local in_combat = 
        state.time_of.involved_in_combat ~= nil
        or state.in_cursor == cursor_type.combat
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
        or state.time_of.quickbar_interaction ~= nil
        or not state.settings.hide_quickbar
        or (in_combat and state.settings.show_quickbar_in_combat)

    local show_shortcuts = show_controller_bars
        or state.in_cursor == cursor_type.wire
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
    -- note: hiding the quickbar disables quickbar hotkeys (expected to be fixed in Factorio 2.1)
    player.game_view_settings.show_quickbar = show_quickbar
    player.game_view_settings.show_shortcut_bar = show_shortcuts
    player.game_view_settings.show_alert_gui = show_alerts

    if next(state.time_of) ~= nil then
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
local function update_hud_bacause(event_name, player_index, tick)
    local state = storage.per_player[player_index]
    state.time_of[event_name] = tick
    update_hud(player_index)
end

-- MARK: Initialization

local function setup(player_index)
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
end

local function remove(player_index)
    storage.per_player[player_index] = nil
    for unit_number, related_players in pairs(storage.entity_related_players) do
        related_players[player_index] = nil
        if next(related_players) == nil then
            storage.entity_related_players[unit_number] = nil
        end
    end
end

local function update(player_index)
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

local function init()
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

script.on_init(function()
    init()
end)

script.on_load(function()
    -- When hosting or in singleplayer, storage structure could be still outdated during on_load.
    -- Meaning `on_configuration_changed` is yet to run.
    -- When in multiplayer, the client is provided with post-`on_configuration_changed` save file.
    local mod_version = script.active_mods[script.mod_name]
    if storage.version ~= mod_version then return end

    update_event_bindings()
end)

script.on_configuration_changed(function(event)
    init()
end)

-- MARK: Connect

function bind.events_connection()
    local dynamic_hud_enabled = some(storage.per_player, function(s) return s.online and s.dynamic_hud_enabled end)
    if dynamic_hud_enabled and not events_dispatch.connected then
        events_dispatch:connect()
    elseif not dynamic_hud_enabled and events_dispatch.connected then
        events_dispatch:disconnect()
    end
end

script.on_event(own"activate", function(event)
    local state = storage.per_player[event.player_index]
    state.dynamic_hud_enabled = not state.dynamic_hud_enabled

    if state.dynamic_hud_enabled and not events_dispatch.connected then
        -- Synchronize all state with possibly changed reality.
        -- Note: As long as `events_dispatch` is connected every per-player state is up-to-date
        --       regardless of their `dynamic_hud_enabled`.
        init()
    else
        update_hud(event.player_index)
        bind.events_connection()
    end
end)

function sync.online_status(state, player)
    state.online = player.connected
end

script.on_event(defines.events.on_player_joined_game, function(event)
    setup(event.player_index)
    update(event.player_index)
    update_event_bindings()
end)

script.on_event(defines.events.on_player_left_game, function(event)
    storage.per_player[event.player_index].online = false
    update_event_bindings()
end)

script.on_event(defines.events.on_player_removed, function(event)
    remove(event.player_index)
    update_event_bindings()
end)

events_dispatch:on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if not is_own(event.setting) then return end

    if event.setting_type == "runtime-per-user" and event.player_index ~= nil then
        update(event.player_index)
    end

    -- For any long running timers that are controlled by settings.
    update_event_bindings()
end)

-- MARK: General UI

-- The system UI elements somehow aren't affected
-- while the new game cutscene is playing
events_dispatch:on_event(defines.events.on_cutscene_cancelled, function(event)
    update_hud_bacause("ui_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(defines.events.on_cutscene_finished, function(event)
    update_hud_bacause("ui_updated", event.player_index, event.tick)
end)

function sync.opened_gui(state, player)
    state.opened_gui = player.opened_gui_type
end

events_dispatch:on_event(defines.events.on_gui_opened, function(event)
    local player = game.get_player(event.player_index)
    local state = storage.per_player[event.player_index]

    sync.opened_gui(state, player)

    update_hud(event.player_index)
end)

events_dispatch:on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)
    local state = storage.per_player[event.player_index]

    sync.opened_gui(state, player)

    if event.gui_type == defines.gui_type.controller then
        state.time_of.inventory_closed = event.tick
    end

    update_hud(event.player_index)
end)

events_dispatch:on_event(own"open-character-gui", function(event)
    local player = game.get_player(event.player_index)
    if player.controller_type == defines.controllers.spectator then
        update_hud_bacause("inventory_closed", event.player_index, event.tick)
    end
end)

events_dispatch:on_event(own"increase-ui-scale", function(event)
    update_hud_bacause("ui_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(own"decrease-ui-scale", function(event)
    update_hud_bacause("ui_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(own"reset-ui-scale", function(event)
    update_hud_bacause("ui_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(defines.events.on_player_controller_changed, function(event)
    local state = storage.per_player[event.player_index]
    state.time_of.controller_changed = event.tick
    -- It is possible to sit into a vehicle and then remotely "enter" another vehicle.
    -- `on_player_driving_changed_state` won't fire when going back.
    sync.driving_mode(state, game.get_player(event.player_index))
    update_hud(event.player_index)
end)

events_dispatch:on_event(defines.events.on_player_changed_surface, function(event)
    update_hud_bacause("surface_changed", event.player_index, event.tick)
end)

local function on_active_research_updated(tick, force)
    for _, player in pairs(force.players) do
        update_hud_bacause("research_updated", player.index, tick)
    end
end

events_dispatch:on_event(defines.events.on_research_started, function(event)
    on_active_research_updated(event.tick, event.research.force)
end)

events_dispatch:on_event(defines.events.on_research_finished, function(event)
    on_active_research_updated(event.tick, event.research.force)
end)

events_dispatch:on_event(defines.events.on_research_cancelled, function(event)
    -- the goal is to update HUD only if the queue head was cancelled
    -- if queue is still not empty then `started` would fire for next tech
    if #event.force.research_queue == 0 then
        on_active_research_updated(event.tick, event.force)
    end
end)

events_dispatch:on_event(own"pin", function(event)
    -- There is no API to hide list of pins.
    -- Also it doesn't appear if right side views are currently hidden,
    -- but it doesn't hide when right side views are told to hide.
    -- See https://forums.factorio.com/viewtopic.php?t=133423
    -- Show minimap to force list of pins out of hiding.
    update_hud_bacause("minimap_updated", event.player_index, event.tick)
end)

-- MARK: Alerts

local function on_check_alerts_tick(event)
    for _, player in pairs(game.connected_players) do
        local state = storage.per_player[player.index]

        -- Note: game_view_settings.show_alert_gui isn't a good criteria - time_of might need a refresh
        if not state.settings.hide_alerts or not state.dynamic_hud_enabled then
            goto next_player
        end

        -- Note: `get_alerts` cpu time depends on number of active alerts.
        --   It becomes significant when there are thousands of alerts.
        local current_alerts = player.get_alerts{}
        local report_alerts_updated = false

        for surface_index, per_type in pairs(current_alerts) do
            local previous_per_type = set_default(state.alerts_summary, surface_index, {})
            -- Note: the per-type array has 0 indexed value -> ipairs won't work.
            for alert_type, alerts in pairs(per_type) do

                -- Trying to iterate over all the alerts would result in micro-freezes
                -- when e.g. thousands of entities are missing construction materials.
                -- Instead only check alerts count and the specifics of the last alert.
                -- The number of alert types is explicitly limited.
                -- And for surfaces, assume it is also meaningfully limited.
                local previous = set_default(previous_per_type, alert_type, { count = 0 })
                local current_count = #alerts
                local last_alert = current_count > 0 and alerts[current_count] or nil
                local current_entity_id = last_alert and last_alert.target and last_alert.target.unit_number
                local current_message = last_alert and last_alert.message
                local current_icon = last_alert and last_alert.icon
                local current_icon_name = current_icon and current_icon.name
                local current_icon_quality = current_icon and current_icon.quality
                    and (type(current_icon.quality) == "string" and current_icon.quality or current_icon.quality.name)

                if previous.count ~= current_count
                    or previous.entity_id ~= current_entity_id
                    or previous.message ~= current_message
                    or previous.icon_name ~= current_icon_name
                    or previous.icon_quality ~= current_icon_quality
                then
                    previous.count = current_count
                    previous.entity_id = current_entity_id
                    previous.message = current_message
                    previous.icon_name = current_icon_name
                    previous.icon_quality = current_icon_quality

                    -- no need to show panel for a disappeared alert
                    if current_count > 0 then
                        report_alerts_updated = true
                    end
                end

            end
        end

        if player.character then
            local followers = player.character.following_robots
            local followers_count = #followers
            local last_follower_id = followers_count > 0 and followers[followers_count].unit_number or 0

            local previous = set_default(state.alerts_summary, "following_robots", { count = 0 })
            if previous.count ~= followers_count or previous.entity_id ~= last_follower_id then
                previous.count = followers_count
                previous.entity_id = last_follower_id

                if followers_count > 0 then
                    report_alerts_updated = true
                end
            end
        end

        for surface in pairs(state.alerts_summary) do
            if type(surface) == "number" and not current_alerts[surface] then
                state.alerts_summary[surface] = nil
            end
        end

        if report_alerts_updated then
            update_hud_bacause("alerts_updated", player.index, event.tick)
        end

        ::next_player::
    end
end

local alerts_check_running
function bind.alerts_checking()
    local hide_alerts = some(storage.per_player, function(s) return s.online and s.settings.hide_alerts end)

    if hide_alerts and not alerts_check_running then
        alerts_check_running = events_dispatch:on_nth_tick(alerts_check_period, on_check_alerts_tick)

    elseif not hide_alerts and alerts_check_running then
        events_dispatch:cancel(alerts_check_running)
        alerts_check_running = nil
    end
end

-- MARK: Cursor

function sync.in_cursor(state, player)
    local cursor_stack = player.cursor_stack
    local in_cursor = nil
    if cursor_stack and cursor_stack.valid_for_read then
        if is_wire[cursor_stack.name] then
            in_cursor = cursor_type.wire

        elseif cursor_stack.prototype.group.name == "combat"
            or cursor_stack.prototype.capsule_action  -- e.g. fish is not in combat group
                and cursor_stack.name ~= "cliff-explosives"  -- not for combat
                and cursor_stack.name ~= "artillery-targeting-remote"  -- no direct involvment
        then
            in_cursor = cursor_type.combat
        end
    end
    state.in_cursor = in_cursor
end

events_dispatch:on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local state = storage.per_player[event.player_index]
    local player = game.get_player(event.player_index)
    local in_cursor_before = state.in_cursor
    sync.in_cursor(state, player)

    if state.in_cursor ~= in_cursor_before then
        if state.in_cursor ~= cursor_type.wire and in_cursor_before == cursor_type.wire then
            state.time_of.wire_cursor_dropped = event.tick
        end
        if state.in_cursor ~= cursor_type.combat and in_cursor_before == cursor_type.combat then
            state.time_of.combat_cursor_dropped = event.tick
        end

        -- Note: cursor_stack_changed might be called frequently
        -- e.g. when building a belt by dragging.
        -- No need to re-update when there were no changes to cursor kind.
        update_hud(event.player_index)
    end
end)

-- MARK: Combat

events_dispatch:on_event(own"next-weapon", function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(defines.events.on_player_armor_inventory_changed, function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(defines.events.on_player_gun_inventory_changed, function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(defines.events.on_player_ammo_inventory_changed, function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(own"shoot-enemy", function(event)
    local state = storage.per_player[event.player_index]
    state.time_of.involved_in_combat = event.tick
    state.time_of.toolbar_updated = event.tick
    update_hud(event.player_index)
end)

events_dispatch:on_event(own"shoot-selected", function(event)
    update_hud_bacause("toolbar_updated", event.player_index, event.tick)
end)

events_dispatch:on_event(defines.events.on_entity_damaged, function(event)
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

-- MARK: Driving

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

events_dispatch:on_event(defines.events.on_player_driving_changed_state, function(event)
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

events_dispatch:on_event(defines.events.on_object_destroyed, function(event)
    if event.type ~= defines.target_type.entity then return end
    local related_players = storage.entity_related_players[event.useful_id]
    if not related_players then return end

    for player_index in pairs(related_players) do
        sync.driving_mode(storage.per_player[player_index], game.get_player(player_index))
        update_hud(player_index)
    end
    storage.entity_related_players[event.useful_id] = nil
end)

-- MARK: Quickbar

local function update_hud_with_quickbar_workaround(player_index, tick)
    if game.get_player(player_index).game_view_settings.show_quickbar then
        update_hud_bacause("quickbar_interaction", player_index, tick)
        return
    end

    -- When un-hiding the quickbar immediately during handling of a quickbar switch hotkey,
    -- it shows up with outdated state (the state before switching).
    -- See https://forums.factorio.com/viewtopic.php?t=133378

    on_next_tick(function()
        update_hud_bacause("quickbar_interaction", player_index, tick)
    end)
end

events_dispatch:on_event(own"rotate-active-quick-bars", function(event)
    update_hud_with_quickbar_workaround(event.player_index, event.tick)
end)

local function shift_selected_quickbar_workaround(direction, player_index, tick)
    if game.get_player(player_index).game_view_settings.show_quickbar then
        update_hud_bacause("quickbar_interaction", player_index, tick)
        return
    end

    -- Some quickbar selection hotkeys aren't working while quickbar is hidden.
    -- Workaround: do selection yourself.
    -- See https://forums.factorio.com/viewtopic.php?t=133377

    local player = game.get_player(player_index)
    local selected_before = player.get_active_quick_bar_page(1)

    on_next_tick(function()
        local selected_after = player.get_active_quick_bar_page(1)
        -- Detect if the bug is still there.
        if selected_after == selected_before then
            player.set_active_quick_bar_page(1, (10 + selected_after - 1 + direction) % 10 + 1)
        end
        update_hud_bacause("quickbar_interaction", player_index, tick)
    end)
end

events_dispatch:on_event(own"next-active-quick-bar"	, function(event)
    shift_selected_quickbar_workaround(1, event.player_index, event.tick)
end)

events_dispatch:on_event(own"previous-active-quick-bar", function(event)
    shift_selected_quickbar_workaround(-1, event.player_index, event.tick)
end)

for i = 1, 10 do
    events_dispatch:on_event(own("action-bar-select-page-"..i), function(event)
        update_hud_with_quickbar_workaround(event.player_index, event.tick)
    end)
end

local function pick_quickslot_workaround(player, tick, quickbar_screen_page, quickbar_slot)
    -- As of Factorio v2.0.76, Quickbar slot hotkeys aren't working while quickbar is hidden.
    -- Expected to be fixed in v2.1.
    -- Workaround: reimplement quickbar hotkeys from scratch.
    -- See https://forums.factorio.com/viewtopic.php?t=133377

    -- The re-implementation is not perfect.
    --   - Uniq items (blueprints, remotes) cannot be distinquished from each other.
    --   - Slots with blueprints from bp library are reported by API as empty slots.
    --   - The "hand" icon in inventory doesn't appear.
    --   - Selected slot is not highlighted.

    local cursor_stack = player.cursor_stack
    if not cursor_stack then return end

    local cursor_item_before = cursor_stack.valid_for_read and (cursor_stack.item or cursor_stack) or nil
    local cursor_record_before = player.cursor_record
    local cursor_ghost_before = player.cursor_ghost

    -- Give game a chance to properly handle hotkey before applying workaround.
    on_next_tick(function()

        local cursor_item_after = cursor_stack.valid_for_read and (cursor_stack.item or cursor_stack) or nil
        local cursor_record_after = player.cursor_record
        local cursor_ghost_after = player.cursor_ghost

        local function match(before, after)
            return before == after or before and after and item_match(before, after)
        end
        local same_cursor_as_before =
            match(cursor_item_before, cursor_item_after)
            and match(cursor_record_before, cursor_record_after)
            and match(cursor_ghost_before, cursor_ghost_after)

        -- Detect if bug is not fixed.
        -- If there are changes to the cursor then the bug is probably fixed.
        -- Otherwise, cases that will give false positive:
        --   - having picked non-uniq item, selected quickslot with same entity type
        --   - having selected a quickslot, selected different quickslot with same setup
        --   - having empty cursor, selected empty quickslot
        if not same_cursor_as_before then return end

        local selected_page = player.get_active_quick_bar_page(quickbar_screen_page)
        local quickslot_filter = player.get_quick_bar_slot(10*(selected_page-1)+quickbar_slot)
        if type(quickslot_filter) == "string" then
            quickslot_filter = { name = quickslot_filter, quality = "normal" }
        end

        -- As there is no way of distinguishing which blueprint or planner is set for the quickslot,
        -- consider all blueprints and planners as empty slots.
        --
        -- Aside from the above and really empty slots, a slot with a remote
        -- or a blueprint from bp library is also reported by the game as "empty".
        -- The only thing left is tell the user the hotkey doesn't work
        -- by clearing the cursor and bringing up the Quickbar.
        if quickslot_filter and (
            quickslot_filter.name == "blueprint"
            or quickslot_filter.name == "blueprint-book"
            or quickslot_filter.name == "deconstruction-planner"
            or quickslot_filter.name == "upgrade-planner")
        then
            quickslot_filter = nil
        end

        if not quickslot_filter then
            update_hud_bacause("quickbar_interaction", player.index, tick)
        end

        -- Cases:
        --   empty cursor, found in inventory -> transfer to cursor
        --   cursor with item, found in inventory -> swap
        --   cursor with item, missing in inventory -> ghost
        --      ^ same but required item is already in cursor -> do nothing
        --   selected quickslot is empty -> clear cursor

        -- Check if cursor needs to be updated.
        -- Ideally repeated press of the same quickslot should clear cursor,
        -- But if there are multiple quickslots with same filter,
        -- there is no way of knowing which one was selected before.
        if
            not quickslot_filter and (
                not cursor_stack.valid_for_read
                and player.cursor_record == nil
                and player.cursor_ghost == nil
            )
            or quickslot_filter and (
                cursor_stack.valid_for_read and item_match(cursor_stack, quickslot_filter)
                or (not cursor_stack.valid_for_read and player.cursor_ghost
                    and item_match(player.cursor_ghost, quickslot_filter))
            )
        then return end

        local inventory = player.get_main_inventory()
        if not inventory then return end

        function play_cursor_stack_sound(action)
            local sound_path, volume
            if cursor_stack.valid_for_read then
                sound_path, volume = action.."/"..cursor_stack.name, 0.75
            elseif action == "item-pick" and not player.cursor_ghost
                or action == "item-drop" and player.cursor_ghost then
                sound_path, volume = "utility/clear_cursor", 1.0
            end
            if sound_path and helpers.is_valid_sound_path(sound_path) then
                -- in the real implementation different sounds are played with different volume
                player.play_sound{path = sound_path, volume_modifier = volume}
            end
        end

        play_cursor_stack_sound("item-drop")

        local inventory_stack = quickslot_filter and inventory.find_item_stack(quickslot_filter)
        if inventory_stack then
            cursor_stack.swap_stack(inventory_stack)  -- works for empty cursor too
            player.cursor_ghost = nil

            play_cursor_stack_sound("item-pick")

        else
            -- Note: `cursor_record` is readonly
            if player.clear_cursor() then
                if quickslot_filter and is_wire[quickslot_filter.name] then
                    cursor_stack.set_stack(quickslot_filter)
                    player.cursor_stack_temporary = true
                else
                    player.cursor_ghost = quickslot_filter
                end

                play_cursor_stack_sound("item-pick")
                -- Note: if inventory is full `clear_cursor()` will play the error sound
                --   and show appropriate hint. No need to do it ourselves.
            end
        end
    end)
end

local function on_quickslot_button(screen_page, slot_index, event)
    local state = storage.per_player[event.player_index]
    local player = game.get_player(event.player_index)
    if not player.game_view_settings.show_quickbar and state.settings.quickbar_workaround_enabled then
        pick_quickslot_workaround(player, event.tick, screen_page, slot_index)
    end

    if state.settings.show_quickbar_on_use then
        update_hud_bacause("quickbar_interaction", event.player_index, event.tick)
    end
end

for i = 1, 10 do
    events_dispatch:on_event(own("quick-bar-button-"..i), function(event)
        on_quickslot_button(1, i, event)
    end)
    events_dispatch:on_event(own("quick-bar-button-"..i.."-secondary"), function(event)
        on_quickslot_button(2, i, event)
    end)
end

events_dispatch:on_event(defines.events.on_player_set_quick_bar_slot, function(event)
    update_hud_bacause("quickbar_interaction", event.player_index, event.tick)
end)
