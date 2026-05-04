-- `info.lua` is a mod-specific config file
local info = require("info")

local own_prefix = info.own_namespace .. "_"

function own(name)
    return own_prefix .. name
end

function is_own(name)
    return string.sub(name, 1, #own_prefix) == own_prefix
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

-- Returns `true` if enough time have passed since last `true`.
function throttle(storage, key, threshold, tick)
    local last_tick = storage[key]
    if not last_tick or (tick - last_tick >= threshold) then
        storage[key] = tick
        return true
    end
    return false
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
    ---@field raw table<string, any>
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
    ---@field forces table<integer, any>
    ---@field print fun(msg: string)
    game = game

    ---@class (exact) LuaSettings
    ---@field get_player_settings fun(player_index: integer): table<string, { value: number|boolean|string }>
    ---@field startup table<string, { value: number|boolean|string }>
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
