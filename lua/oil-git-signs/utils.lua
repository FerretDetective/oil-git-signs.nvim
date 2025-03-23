local M = {}

local unpack = unpack or table.unpack

---Import a module lazily such that it won't load until necessary
---@param modname string
function M.lazy_require(modname)
    local mod = nil

    return setmetatable({}, {
        __index = function(_, key)
            if mod == nil then
                mod = require(modname)
            end

            return mod[key]
        end,
        __newindex = function(_, key, value)
            mod[key] = value
        end,
    })
end

---Return start and stop line numbers of the current visual selection,
---or the current cursor position when not in visual mode.
---@return integer
---@return integer
function M.get_current_positions()
    return vim.fn.getpos("v")[2], vim.fn.getpos(".")[2]
end

---Generate the name of the augroup for the single set of watchers for a given repository
---@param repo_root string
---@return string aug_name
function M.repo_get_augroup_name(repo_root)
    return string.format("OilGitSignsRepoWatcher%s", repo_root)
end

---Generate an augroup for the single set of watchers for a given repository
---@param repo_root string
---@return integer aug_id
function M.repo_get_augroup(repo_root)
    return vim.api.nvim_create_augroup(M.repo_get_augroup_name(repo_root), {})
end

---Generate an augroup for a given buffer
---@param buffer integer buf_nr
---@return string aug_name
function M.buf_get_augroup_name(buffer)
    return string.format("OilGitSigns_buf-%d", buffer)
end

---Generate an augroup for a given buffer
---@param buffer integer buf_nr
---@return integer aug_id
function M.buf_get_augroup(buffer)
    return vim.api.nvim_create_augroup(M.buf_get_augroup_name(buffer), {})
end

---Generate a namespace for a given buffer
---@param buffer integer buf_nr
---@return integer ns_id
function M.buf_get_namespace(buffer)
    return vim.api.nvim_create_namespace(("OilGitSigns_buf-%d"):format(buffer))
end

---Create a wrapper for a function which ensures that function is called at most every `time_ms` millis
---@param fn fun(...: any)
---@param time_ms integer
---@return fun(...: any)
function M.apply_debounce(fn, time_ms)
    local debounce = assert(vim.uv.new_timer(), "failed to create debounce timer")
    local has_pending = false

    return function(...)
        local args = { ... }
        if not debounce:is_active() then
            fn(unpack(args))
        else
            has_pending = true
        end

        debounce:start(
            time_ms,
            0,
            vim.schedule_wrap(function()
                if has_pending then
                    fn(unpack(args))
                    has_pending = false
                end
            end)
        )
    end
end

---Wrap a function with a lightweight cache to save results.
---@generic T
---@param fn fun(...: any): T
---@param cache table<any[], T>?
---@return fun(...: any): T
function M.memoize(fn, cache)
    cache = cache or {}

    return function(...)
        local args = { ... }

        local cached = cache[args]
        if cached ~= nil then
            return cached
        end

        local result = fn(...)

        cache[args] = result

        return result
    end
end

---Wrapper around `nvim_feedkeys` calling `nvim_replace_termcodes` first
---@param keys any
---@param mode any
function M.feedkeys(keys, mode)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode or "n", false)
end

local OS_SEP = jit.os:find("Window") and "\\" or "/"

---Make an absolute path relative to a source path
---@param path string
---@param source string?
---@param sep string?
function M.make_relative_path(path, source, sep)
    sep = sep or OS_SEP
    source = source or vim.fn.getcwd()

    local path_parts = vim.split(path, sep)
    local source_parts = vim.split(source, sep)

    local i = 1
    local cur_part = nil
    repeat
        cur_part = source_parts[i]
        i = i + 1
    until cur_part ~= path_parts[i]

    return table.concat(path_parts, sep, i)
end

---Return a formatted message to log
---@param msg string
---@return string
local function format_log(msg)
    return "OilGitSigns: " .. msg
end

---Write a log message using vim.notify
---@param msg string
---@param level integer
---@param opts table?
local function write_log(msg, level, opts)
    vim.schedule(function()
        vim.notify(format_log(msg), level, opts or {})
    end)
end

---Log a message with `vim.notify` with the level info.
---@param msg string
---@param opts table?
function M.info(msg, opts)
    write_log(msg, vim.log.levels.INFO, opts)
end

---Log a message with `vim.notify` with the level debug.
---@param msg string
---@param opts table?
function M.debug(msg, opts)
    write_log(msg, vim.log.levels.DEBUG, opts)
end

---Log a message with `vim.notify` with the level warn.
---@param msg string
---@param opts table?
function M.warn(msg, opts)
    write_log(msg, vim.log.levels.WARN, opts)
end

---Log a message with `vim.notify` with the level error.
---@param msg string
---@param opts table?
function M.error(msg, opts)
    write_log(msg, vim.log.levels.ERROR, opts)
end

---Log a message with `vim.notify` with the level trace.
---@param msg string
---@param opts table?
function M.trace(msg, opts)
    write_log(msg, vim.log.levels.TRACE, opts)
end

return M
