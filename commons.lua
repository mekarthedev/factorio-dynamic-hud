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
    subscribed = false,

    -- #todo: should `on_event` after `subscribe_all` be supported?
    on_event = function(self, event, handler)
        self.handlers[event] = handler
    end,

    subscribe_all = function(self)
        for event, handler in pairs(self.handlers) do
            script.on_event(event, handler)
        end
        self.subscribed = true
    end,

    unsubscribe_all = function(self)
        for event in pairs(self.handlers) do
            script.on_event(event, nil)
        end
        self.subscribed = false
    end,
}

ticks_dispatch = {
    _oneshot_handlers = {},

    _continue = function(self, n)
        script.on_nth_tick(n, function(event)
            local current_batch = self._oneshot_handlers[n]
            self._oneshot_handlers[n] = nil
            for _, handle in pairs(current_batch) do
                handle(event)
            end
            if self._oneshot_handlers[n] == nil then
                script.on_nth_tick(n, nil)
            end
        end)
    end,

    on_nth_tick_once = function(self, n, handler)
        local handlers = set_default(self._oneshot_handlers, n, {})
        table.insert(handlers, handler)
        self:_continue(n)
    end,
}

function on_next_tick(oneshot_action)
    ticks_dispatch:on_nth_tick_once(1, oneshot_action)
end

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

-- Common lua utilities

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
