-- `info.lua` is a mod-specific config file
local info = require("info")

local own_prefix = info.own_namespace .. "_"

function own(name)
    return own_prefix .. name
end

function is_own(name)
    return string.sub(name, 1, #own_prefix) == own_prefix
end

-- MARK: events_dispatch

-- Register possible continuations by adding them to this table.
-- Registered continuations can then be used with `events_dispatch` as event handlers.
---@alias ContinuationName string
---@alias ContinuationClosure unknown[]
---@alias Continuation [ContinuationName, ContinuationClosure]
---@type {
---  [ContinuationName]: fun(closure: ContinuationClosure, ...),
---  notify: fun(self, handler: Continuation, event: unknown)
---}
continuations = {
    notify = function (self, handler, event)
        self[handler[1]](handler[2], event)
    end
}

events_dispatch = {
    handlers = {
        events = {},  -- { [type]: { [key]: handler } }
        nth_tick = {},  -- { [n]: { [key]: handler } }
    },
    next_key = 1,
    connected = false,

    -- Expected to be called before connect.
    -- Until then, continuations cannot be used as event handlers.
    use_storage = function (self, storage)
        self.storage = storage
        set_default(storage, "continuations", {})  -- { [key]: { key, type, handler } }
        set_default(storage, "next_key", 1)

        for key, sub in pairs(storage.continuations) do
            local handlers = set_default(self.handlers[sub.kind], sub.type, {})
            handlers[key] = sub.handler
        end
    end,

    notify = function (self, kind, event_type, event)
        local handlers = self.handlers[kind][event_type]
        if not handlers then return false end  -- shouldn't happen

        local batch_last_key = 0
        for key in pairs(handlers) do
            batch_last_key = math.max(key, batch_last_key)
        end
        for key, handle in pairs(handlers) do
            if key <= batch_last_key then
                if type(handle) == "function" then
                    handle(event)
                else
                    continuations:notify(handle, event)
                end
            end
        end

        return self.handlers[kind][event_type] ~= nil
    end,

    connection = {
        events = {
            continue = function(self, event_type)
                if not self.connected then return end
                script.on_event(event_type, function(event)
                    self:notify("events", event_type, event)
                end)
            end,
            cancel = function (self, event_type)
                script.on_event(event_type, nil)
            end
        },

        nth_tick = {
            continue = function(self, n)
                if not self.connected then return end
                script.on_nth_tick(n, function(event)
                    self:notify("nth_tick", n, event)
                end)
            end,
            cancel = function (self, n)
                script.on_nth_tick(n, nil)
            end,
        },
    },

    -- continuation = [keyof(continuations), ...paramsof(continuations[string])]
    -- subscription = { kind: string, type: seconds|keyof(defines.events), key: integer }
    -- handler: func|continuation
    -- return: subscription
    -- If handler is save-stable (i.e. is a continuation) then subscription is also save-stable.
    -- Continuations are only allowed after `use_storage`.
    add_handler = function(self, kind, event_type, handler)
        local key
        if type(handler) == "function" then
            -- Make sure local keys don't intersect with save-stable keys from storage
            -- by making local keys negative.
            key = -self.next_key
            self.next_key = self.next_key + 1
        else
            key = self.storage.next_key
            self.storage.next_key = self.storage.next_key + 1
            self.storage.continuations[key] = { kind = kind, type = event_type, handler = handler }
        end

        local handlers = set_default(self.handlers[kind], event_type, {})
        handlers[key] = handler
        self.connection[kind].continue(self, event_type)

        return { kind = kind, type = event_type, key = key }
    end,

    on_event = function(self, event_type, handler)
        return self:add_handler("events", event_type, handler)
    end,

    on_nth_tick = function(self, n, handler)
        return self:add_handler("nth_tick", n, handler)
    end,

    cancel = function(self, sub)
        local handlers = self.handlers[sub.kind][sub.type]
        handlers[sub.key] = nil
        self.storage.continuations[sub.key] = nil
        if not next(handlers) then
            self.handlers[sub.kind][sub.type] = nil
            self.connection[sub.kind].cancel(self, sub.type)
        end
    end,

    connect = function (self)
        self.connected = true
        for kind, connection in pairs(self.connection) do
            for event_type in pairs(self.handlers[kind]) do
                connection.continue(self, event_type)
            end
        end
    end,

    disconnect = function (self)
        self.connected = false
        for kind, connection in pairs(self.connection) do
            for event_type in pairs(self.handlers[kind]) do
                connection.cancel(self, event_type)
            end
        end
    end,
}

-- Note: Only a continuation is allowed here.
--   Passing a function could have been technically valid
--   but it would potentially fail `on_load`'s check of "same set of events".
---@param oneshot_action Continuation
function on_next_tick(oneshot_action)
    local sub = {}
    sub.ref = events_dispatch:on_nth_tick(1, {"handle_next_tick", {oneshot_action, sub}})
end
function continuations.handle_next_tick(c)
    local oneshot_action, sub = c[1], c[2]
    events_dispatch:cancel(sub.ref)
    continuations:notify(oneshot_action)
end

-- MARK: Factorio specifics

ticks_per_second = 60

-- Note: There are many functions/properties in Factorio API
-- that can be accessed "only if entity is a Vehicle".
-- This is the only known way to check if an entity is a "vehicle".
is_vehicle_type = {
    ["car"] = true,
    ["spider-vehicle"] = true,
    ["locomotive"] = true,
    -- technically these are also vehicles
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true
}

is_wire = {
    ["red-wire"] = true,
    ["green-wire"] = true,
    ["copper-wire"] = true,
}

-- get the player controlling this entity (character, car, etc.)
function player_index_of(entity)
    local player = nil
    if entity.type == "character" then
        player = entity.player

    elseif is_vehicle_type[entity.type] then
        local driver = entity.get_driver()
        -- driver is player when driving remotely
        if driver and not driver.is_player() then
            player = driver.player
        else
            player = driver
        end
    end
    return player and player.index
end

function item_match(item_like, filter_like)
    local item_name = type(item_like.name) == "string" and item_like.name or item_like.name.name
    local item_quality = type(item_like.quality) == "string" and item_like.quality or item_like.quality.name
    local filter_name = type(filter_like.name) == "string" and filter_like.name or filter_like.name.name
    local filter_quality = type(filter_like.quality) == "string" and filter_like.quality or filter_like.quality.name
    return item_name == filter_name and item_quality == filter_quality
end

-- MARK: Common lua

function set_default(table, key, initial_value)
    local value = table[key]
    if value == nil then
        table[key] = initial_value
        value = initial_value
    end
    return value
end

function every(tbl, predicate)
    for _, value in pairs(tbl) do
        if not predicate(value) then
            return false
        end
    end
    return true
end

function some(tbl, predicate)
    for _, value in pairs(tbl) do
        if predicate(value) then
            return true
        end
    end
    return false
end

-- MARK: Types

if false then
    ---@class (exact) Data
    ---@field extend fun(self, other: table[])
    data = data

    ---@class (exact) Defines
    ---@field events table<string, integer>
    ---@field gui_type table<string, integer>
    ---@field target_type table<string, integer>
    ---@field alert_type table<string, integer>
    ---@field controllers table<string, integer>
    defines = defines

    ---@class (exact) LuaBootstrap
    ---@field on_init fun(handler: nil|fun())
    ---@field on_load fun(handler: nil|fun())
    ---@field on_configuration_changed fun(handler: nil|fun(data))
    ---@field on_nth_tick fun(tick: integer, handler: nil|fun(e: { tick: integer }))
    ---@field on_event fun(event_type: string|integer, handler: nil|fun(e))
    ---@field register_on_object_destroyed fun(object: table)
    ---@field active_mods table<string, string>
    ---@field mod_name string
    script = script

    ---@class (exact) LuaGameScript
    ---@field get_player fun(player_index: integer): any
    ---@field players table<integer, any>
    ---@field connected_players any[]
    ---@field print fun(msg: string)
    game = game

    ---@class (exact) LuaSettings
    ---@field get_player_settings fun(player_index: integer): table<string, { value: number|boolean|string }>
    settings = settings

    ---@type table<string, any>
    storage = storage

    ---@class (exact) LuaHelpers
    ---@field is_valid_sound_path fun(path: string): boolean
    helpers = helpers

    ---@class (exact) Serpent
    ---@field block fun(value): string
    serpent = serpent

    ---@type fun(msg: string)
    log = log
end
