-- `info.lua` is a mod-specific config file
local info = require("info")

function own(name)
  return info.own_namespace .. "__" .. name
end

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
