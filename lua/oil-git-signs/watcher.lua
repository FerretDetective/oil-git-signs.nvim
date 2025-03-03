---@class oil_git_signs.FsWatcher
---@field _filepath string
---@field _callbacks table<integer, nil|fun(err: string|nil, filename: string, events: uv.fs_event_start.callback.events)>
---@field _current_handle integer
---@field _fs_event uv.uv_fs_event_t|nil
local FsWatcher = {}

---Create a new `FsWatcher`
---@param filepath string valid normalized filepath (i.e. you are responsible for validating and normalizing the path)
---@return oil_git_signs.FsWatcher
function FsWatcher.new(filepath)
    local self = setmetatable({}, { __index = FsWatcher })

    self._filepath = filepath
    self._callbacks = {}
    self._current_handle = 0
    self._fs_event = nil

    return self
end

---Register a callback to be called on the `uv.fs_event`
---@param callback fun(err: string|nil, filename: string, events: uv.fs_event_start.callback.events)
---@return integer handle
function FsWatcher:register_callback(callback)
    local handle = self:_get_new_handle()
    self._callbacks[handle] = callback

    return handle
end

---Deregister a callback from being called on the `uv.fs_event`
---@param handle integer
---@return boolean success, nil|fun(err: string|nil, filename: string, events: uv.fs_event_start.callback.events) callback
---
---@overload fun(handle: integer): true, fun(err: string|nil, filename: string, events: uv.fs_event_start.callback.events)
---@overload fun(handle: integer): false, nil
function FsWatcher:deregister_callback(handle)
    local callback = self._callbacks[handle]
    self._callbacks[handle] = nil

    return callback ~= nil, callback
end

---Starting watching the `FsWatcher.filepath`
---@param flags? uv.fs_event_start.flags
---@return boolean success, nil|uv.error.message err, nil|uv.error.name err_name
---
---@overload fun(flags?: uv.fs_event_start.flags): false, uv.error.message, uv.error.name
---@overload fun(flags?: uv.fs_event_start.flags): true, nil, nil
function FsWatcher:start(flags)
    local fs_event, err, err_name = vim.uv.new_fs_event()

    if err ~= nil then
        return false, err, err_name
    end
    self._fs_event = assert(fs_event)

    _, err, err_name = self._fs_event:start(self._filepath, flags or {}, function(...)
        for _, cb in ipairs(self._callbacks) do
            pcall(cb, ...)
        end
        self:start(flags)
    end)

    return err == nil, err, err_name
end

---Starting watching the `FsWatcher.filepath`
---@return boolean success, nil|uv.error.message err, nil|uv.error.name err_name
---
---@overload fun(): true, nil, nil
---@overload fun(): false, uv.error.message?, uv.error.name?
function FsWatcher:stop()
    if self._fs_event == nil then
        return true, nil, nil
    end

    local _, err, err_name = vim.uv.fs_event_stop(self._fs_event)

    return err == nil, err, err_name
end

function FsWatcher:_get_new_handle()
    self._current_handle = self._current_handle + 1
    return self._current_handle
end

return FsWatcher
