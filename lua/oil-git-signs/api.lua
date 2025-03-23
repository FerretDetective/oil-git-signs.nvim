local M = {}

local config = require("oil-git-signs.config")
local extmarks = require("oil-git-signs.extmarks")
local git = require("oil-git-signs.git")
local utils = require("oil-git-signs.utils")

local oil_utils = require("oil.util")

---Navigate the cursor to an entry with a given status.
---
---Defaults:
---statuses: all available git statuses are used
---count: 1 is the default count, use -1 to get the last occurence, -2 to get the second last, ...
---
---@param direction "up"|"down"
---@param count integer?  1 by default
---@param statuses { index: oil_git_signs.GitStatus[], working_tree: oil_git_signs.GitStatus[] }?  all by default
function M.jump_to_status(direction, count, statuses)
    if not vim.b.oil_git_signs_exists then
        utils.error("not a git repository")
        return
    end

    if count == 0 then
        return
    end

    count = count or 1
    statuses = statuses or { index = git.AllStatuses, working_tree = git.AllStatuses }

    -- the strings are used to match against each status as `vim.tbl_contains` is more expensive
    local index_pattern = "^$"
    if #statuses.index > 0 then
        index_pattern = ("[%s]"):format(table.concat(statuses.index))
    end

    local working_tree_pattern = "^$"
    if #statuses.working_tree > 0 then
        working_tree_pattern = ("[%s]"):format(table.concat(statuses.working_tree))
    end

    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local buf_len = vim.api.nvim_buf_line_count(buf)
    local cursor_row = vim.api.nvim_win_get_cursor(win)[1]

    local start, stop, step
    if direction == "down" then
        if count > 0 then
            -- start at the cursor and move down
            start = cursor_row + 1
            stop = buf_len
            step = 1
        else
            -- start at the end and move up (e.g. getting the last status)
            start = buf_len
            stop = cursor_row
            step = -1
        end
    elseif direction == "up" then
        if count > 0 then
            -- start at the cursor and move up
            start = cursor_row - 1
            stop = 1
            step = -1
        else
            -- start at the top and move down (e.g. getting the first status)
            start = 1
            stop = cursor_row
            step = 1
        end
    else
        utils.error(("'%s' is not a valid direction"):format(direction))
        return
    end

    -- count must be positive in order to be used to the determine how many statuses we need to visit
    count = math.abs(count)

    local jump_list = extmarks.BufferJumpLists[buf]

    -- ensure the jump_list is valid in the buffer before jumping (i.e. not out of sync)
    if jump_list ~= nil then
        for lnum = start, stop, step do
            local line_status = jump_list[lnum]

            if line_status ~= nil then
                if
                    line_status:sub(1, 1):match(index_pattern)
                    or line_status:sub(2, 2):match(working_tree_pattern)
                then
                    count = count - 1
                end

                if count == 0 then
                    vim.api.nvim_win_set_cursor(win, { lnum, 0 })
                    return
                end
            end
        end
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
        local oil = require("oil")

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
        local oil = require("oil")

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
---local oil_utils = require("oil.util")
---local oil_git = require("oil-git-signs.git")
---
---local buf = vim.api.nvim_get_current_buf()
---local buf_name = vim.api.nvim_buf_get_name(buf)
---local _, oil_dir = oil_utils.parse_url(buf_name)
---local repo_root_path = oil_git.get_root(assert(oil_dir))
---```
---@param repo_root_path string? if nil and in an oil buffer, try that buffer's repo_root else fail
function M.refresh_git_status(repo_root_path)
    if repo_root_path == nil then
        if vim.bo.filetype ~= "oil" then
            utils.error("repo_root_path is missing, and it cannot be inferred for a non-oil buffer")
            return
        end

        local buf = vim.api.nvim_get_current_buf()
        local buf_name = vim.api.nvim_buf_get_name(buf)
        local _, oil_dir = oil_utils.parse_url(buf_name)
        assert(oil_dir, "failed to parse oil url")

        repo_root_path = git.get_root(oil_dir)
    end

    vim.schedule(function()
        vim.api.nvim_exec_autocmds("User", {
            pattern = "OilGitSignsQueryGitStatus",
            data = { repo_root_path = repo_root_path },
        })
    end)
end

return M
