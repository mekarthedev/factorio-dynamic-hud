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
