-- `info.lua` is a mod-specific config file
local info = require("info")

local own_prefix = info.own_namespace .. "_"

function own(name)
    return own_prefix .. name
end

function is_own(name)
    return string.sub(name, 1, #own_prefix) == own_prefix
end

ticks_per_second = 60

subscriptions = {
    handlers = {},

    -- #todo: should `on_event` after `subscribe_all` be supported?
    on_event = function(self, event, handler)
        self.handlers[event] = handler
    end,

    subscribe_all = function(self)
        for event, handler in pairs(self.handlers) do
            script.on_event(event, handler)
        end
    end,

    unsubscribe_all = function(self)
        for event in pairs(self.handlers) do
            script.on_event(event, nil)
        end
    end,
}

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

-- get the player controlling this entity (character, car, etc.)
function player_index_of(entity)
    local character = nil
    if entity.type == "character" then
        character = entity
    elseif is_vehicle_type[entity.type] then
        character = entity.get_driver()
    end
    return character and character.player and character.player.index
end

-- Common lua utilities

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
