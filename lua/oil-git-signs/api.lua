local M = {}

local config = require("oil-git-signs.config")
local git = require("oil-git-signs.git")
local utils = require("oil-git-signs.utils")

local oil = require("oil")

---Navigate the cursor to an entry with a given status.
---
---If `count` < 0, then it will jump to the |`count`|-th last entry, stopping at the cursor unless
---`wrap` is enabled.
---
---If `count` > 0, then it will jump to the `count`-th entry, stopping at the start/end of the
---buffer unless `wrap` is enabled.
---
---Defaults:
---  **count**: `vim.v.count1`
---  **statuses**: `{ index = git.AllStatuses, working_tree = git.AllStatuses }`
---  **wrap**: `vim.o.wrapscan`
---
---@param direction "up"|"down"
---@param count integer?
---@param statuses { index: oil_git_signs.GitStatus[], working_tree: oil_git_signs.GitStatus[] }?
---@param wrap boolean?
function M.jump_to_status(direction, count, statuses, wrap)
    if not vim.b.oil_git_signs_exists then
        utils.error("not a git repository")
        return
    end

    if count == 0 then
        return
    end

    if count == nil then
        count = vim.v.count1
    end

    if statuses == nil then
        statuses = { index = git.AllStatuses, working_tree = git.AllStatuses }
    end

    if wrap == nil then
        wrap = vim.o.wrapscan
    end

    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local buf_len = vim.api.nvim_buf_line_count(buf)
    local cursor_lnum = vim.api.nvim_win_get_cursor(win)[1]

    local start, stop, step, wrap_start, wrap_stop, wrap_step
    if direction == "down" then
        if count > 0 then
            -- start at cursor (exclusive) and move down
            start = cursor_lnum + 1
            stop = buf_len
            step = 1

            -- wrap from SOB until cursor (inclusive)
            wrap_start = 1
            wrap_stop = start
            wrap_step = 1
        else
            -- start at EOB and move up (e.g. getting the last status)
            start = buf_len
            stop = cursor_lnum
            step = -1

            -- wrap from cursor (inclusive) until SOB
            wrap_start = stop
            wrap_stop = 1
            wrap_step = -1
        end
    elseif direction == "up" then
        if count > 0 then
            -- start at cursor (exclusive) and move up
            start = cursor_lnum - 1
            stop = 1
            step = -1

            -- wrap from EOB until cursor (inclusive)
            wrap_start = buf_len
            wrap_stop = start
            wrap_step = -1
        else
            -- start at SOB and move down (e.g. getting the first status)
            start = 1
            stop = cursor_lnum
            step = 1

            -- wrap from cursor (inclusive) until EOB
            wrap_start = stop
            wrap_stop = buf_len
            wrap_step = 1
        end
    else
        utils.error(("'%s' is not a valid direction"):format(direction))
        return
    end

    local oil_dir = assert(utils.get_oil_buf_path(buf), "failed to parse oil url")
    local repo_root = assert(git.get_root(oil_dir), "failed to get repo root")
    local repo_status = assert(git.RepoStatusCache[repo_root], "failed to get repo status").status

    -- count must be positive in order to be used to the determine how many statuses we need to visit
    count = math.abs(count)

    ---@param _start integer
    ---@param _stop integer
    ---@param _step 1|-1
    ---@return integer|nil
    local find_nth_entry = function(_start, _stop, _step)
        for lnum = _start, _stop, _step do
            local entry = oil.get_entry_on_line(buf, lnum)

            if not entry then
                utils.error(("failed to parse entry: lnum=%d"):format(lnum))
                return
            end

            local entry_status = repo_status[oil_dir .. entry.name]

            if entry_status ~= nil then
                if
                    vim.tbl_contains(statuses.index, entry_status.index)
                    or vim.tbl_contains(statuses.working_tree, entry_status.working_tree)
                then
                    count = count - 1
                end

                if count == 0 then
                    return lnum
                end
            end
        end

        return nil
    end

    local lnum = find_nth_entry(start, stop, step)
    if lnum == nil and wrap then
        lnum = find_nth_entry(wrap_start, wrap_stop, wrap_step)
    end

    if lnum ~= nil then
        vim.cmd("normal! m'") -- add current cursor position to the jumplist
        vim.api.nvim_win_set_cursor(win, { lnum, 0 })

        return
    end

    utils.warn("no status valid to move to")
end

---Stage the currently selected entries in an oil buffer.
function M.stage_selected()
    if not vim.b.oil_git_signs_exists then
        utils.error("not a git repository")
        return
    end

    local start, stop = utils.get_current_positions()
    if start > stop then
        start, stop = stop, start
    end

    -- Exit visual mode before scheduling to prevent conflicts or hanging when using `confirm()`
    utils.feedkeys("<Esc>")

    vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        local cwd = assert(oil.get_current_dir(buf), "failed to get the oil cwd")

        local paths = {} ---@type string[]
        for lnum = start, stop do
            local entry = oil.get_entry_on_line(buf, lnum)

            if entry == nil then
                utils.error(("failed to parse entry on line %d"):format(lnum))
                return
            end

            local name = entry.name
            if entry.type == "directory" then
                name = name .. "/"
            end

            table.insert(paths, cwd .. name)
        end

        local confirm_enabled = config.options.confirm_git_operations
        if type(confirm_enabled) == "function" then
            confirm_enabled = confirm_enabled(paths)
        end

        if confirm_enabled then
            local is_simple_operation = #paths <= config.options.simple_git_operations.max_stages
            local skip_simple_operation = config.options.skip_confirm_for_simple_git_operations

            if not is_simple_operation or not skip_simple_operation then
                local items = vim.iter(paths)
                    :map(function(path)
                        return ("    - %s"):format(vim.fs.basename(path))
                    end)
                    :join("\n")

                if
                    vim.fn.confirm("Stage the following items?:\n" .. items, "&Yes\n&No", 2) ~= 1
                then
                    return
                end
            end
        end

        local git_root = assert(git.get_root(cwd), "failed to get git root")
        git.stage_files(paths, git_root, function(out)
            if out.code ~= 0 then
                if out.stderr ~= nil then
                    utils.error("failed to stage selected items:\n" .. out.stderr)
                else
                    -- no git error message to give
                    utils.error("failed to stage selected items")
                end
            end
        end)
    end)
end

---Unstage the currently selected entries in an oil buffer.
function M.unstage_selected()
    if not vim.b.oil_git_signs_exists then
        utils.error("not a git repository")
        return
    end

    local start, stop = utils.get_current_positions()
    if start > stop then
        start, stop = stop, start
    end

    -- Exit visual mode before scheduling to prevent conflicts or hanging when using `confirm()`
    utils.feedkeys("<Esc>")

    vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        local cwd = assert(oil.get_current_dir(buf), "failed to get the oil cwd")

        local paths = {} ---@type string[]
        for lnum = start, stop do
            local entry = oil.get_entry_on_line(buf, lnum)

            if entry == nil then
                utils.error(("failed to parse entry on line %d"):format(lnum))
                return
            end

            local name = entry.name
            if entry.type == "directory" then
                name = name .. "/"
            end

            table.insert(paths, cwd .. name)
        end

        local confirm_enabled = config.options.confirm_git_operations
        if type(confirm_enabled) == "function" then
            confirm_enabled = confirm_enabled(paths)
        end

        if confirm_enabled then
            local is_simple_operation = #paths <= config.options.simple_git_operations.max_stages
            local skip_simple_operation = config.options.skip_confirm_for_simple_git_operations

            if not is_simple_operation or not skip_simple_operation then
                local items = vim.iter(paths)
                    :map(function(path)
                        return ("    - %s"):format(vim.fs.basename(path))
                    end)
                    :join("\n")

                if
                    vim.fn.confirm("Unstage the following items?:\n" .. items, "&Yes\n&No", 2) ~= 1
                then
                    return
                end
            end
        end

        local git_root = assert(git.get_root(cwd), "failed to get git root")
        git.unstage_files(paths, git_root, function(out)
            if out.code ~= 0 then
                if out.stderr ~= nil then
                    utils.error("failed to unstage selected items:\n" .. out.stderr)
                else
                    -- no git error message to give
                    utils.error("failed to unstage selected items")
                end
            end
        end)
    end)
end

---Refresh the git status cache for `repo_root_path`.
---
---To get the path to a repo's root from a given oil buffer use the following:
---```lua
---local git = require("oil-git-signs.git")
---local utils = require("oil-git-signs.utils")
---
---local oil_dir = assert(utils.get_oil_buf_path(0))
---local repo_root_path = assert(git.get_root(oil_dir))
---```
---@param repo_root_path string? if nil and in an oil buffer, try that buffer's repo_root else fail
function M.refresh_git_status(repo_root_path)
    if repo_root_path == nil then
        if vim.bo.filetype ~= "oil" then
            utils.error("repo_root_path is missing, and it cannot be inferred for a non-oil buffer")
            return
        end

        local oil_dir = assert(utils.get_oil_buf_path(0), "failed to parse oil url")
        repo_root_path = assert(git.get_root(oil_dir), "failed to get git root")
    end

    vim.schedule(function()
        vim.api.nvim_exec_autocmds("User", {
            pattern = "OilGitSignsQueryGitStatus",
            data = { repo_root_path = repo_root_path },
        })
    end)
end

return M
