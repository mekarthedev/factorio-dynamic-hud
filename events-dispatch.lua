-- Register possible continuations by adding them to this table.
-- Registered continuations can then be used with `events_dispatch` as event handlers.
-- IMPORTANT: continuations can be referenced in storage, and thus are subject to migrations when renamed.
--
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
        internal = {},  -- { [name]: { [key]: handler }}
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

        internal = { continue = function () end, cancel = function () end }
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

    on_internal = function(self, event_name, handler)
        return self:add_handler("internal", event_name, handler)
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
