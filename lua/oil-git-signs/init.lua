local M = {}

---@enum oil_git_signs.GitStatus
M.GitStatus = {
    -- stylua: ignore start
    SUB_MOD_MODIFIED = "m",
    UNMODIFIED       = " ",
    MODIFIED         = "M",
    TYPE_CHANGED     = "T",
    ADDED            = "A",
    DELETED          = "D",
    RENAMED          = "R",
    COPIED           = "C",
    UNMERGED         = "U",
    UNTRACKED        = "?",
    IGNORED          = "!",
    -- stylua: ignore end
}

---@class oil_git_signs.EntryStatus
---@field index oil_git_signs.GitStatus
---@field working_tree oil_git_signs.GitStatus

---@class oil_git_signs.StatusSummary
---@field index { added: integer, removed: integer, modified: integer }
---@field working_tree { added: integer, removed: integer, modified: integer }

---Create a new `StatusSummary` object
---@return oil_git_signs.StatusSummary
local function new_summary()
    return {
        working_tree = { added = 0, removed = 0, modified = 0 },
        index = { added = 0, removed = 0, modified = 0 },
    }
end

---Parse a single line from `git status --short`
---@param raw_status string
---@return string entry
---@return oil_git_signs.GitStatus index
---@return oil_git_signs.GitStatus working_tree
local function parse_git_status(raw_status)
    local index = raw_status:sub(1, 1) ---@type oil_git_signs.GitStatus
    local working_tree = raw_status:sub(2, 2) ---@type oil_git_signs.GitStatus

    local pattern = "^[" .. index .. "][" .. working_tree .. "] "
    if index == M.GitStatus.RENAMED or working_tree == M.GitStatus.RENAMED then
        pattern = pattern .. '"?.+"? -> ?(.+)"?$'
    else
        pattern = pattern .. '"?(.+)"?$'
    end

    -- extract the filename/path
    local path = assert(raw_status:match(pattern)) ---@type string

    -- extract the first part of the path (up to first sep)
    local entry = assert(path:match(("^([^%s]+)"):format(require("oil.fs").sep))) ---@type string

    return entry, index, working_tree
end

---Update the ext marks for the current buffer
---@param path string
---@return table<string, oil_git_signs.EntryStatus?>
---@return oil_git_signs.StatusSummary
local function query_git_status(path)
    -- could use `--porcelain` here for guaranteed compatibility, but parsing it is more diffciult
    -- due to it not being reported as a path relative the the cwd
    local cmd = { "git", "-c", "status.relativePaths=true", "status", "--short" }

    if M.options.show_ignored(path) then
        table.insert(cmd, "--ignored")
    end

    table.insert(cmd, ".")

    local task = vim.system(cmd, { text = true, cwd = path })
    local stdout = assert(task:wait().stdout)

    local statuses = {} ---@type table<string, oil_git_signs.EntryStatus?>
    local summary = new_summary()

    for line in vim.gsplit(stdout, "\n") do
        if line ~= "" then
            local entry, index, working_tree = parse_git_status(line)

            -- update index summary
            local index_status_class = M.options.status_classification[index]
            if index_status_class then
                local count = summary.index[index_status_class]
                summary.index[index_status_class] = count + 1
            end

            -- update working tree summary
            local working_tree_status_class = M.options.status_classification[working_tree]
            if working_tree_status_class then
                local count = summary.working_tree[working_tree_status_class]
                summary.working_tree[working_tree_status_class] = count + 1
            end

            -- in the case where a subdir has multiple objects with unique statuses we need to
            -- resolve the conflict by determining which status has priority
            local existing_entry = statuses[entry]

            if existing_entry == nil then
                -- no collision
                statuses[entry] = { index = index, working_tree = working_tree }
            else
                -- resolve index collision
                local index_score = M.options.status_priority[index]
                local existing_index_score = M.options.status_priority[existing_entry.index]
                if index_score > existing_index_score then
                    existing_entry.index = index
                end

                -- resolve working tree collision
                local working_tree_score = M.options.status_priority[working_tree]
                local existing_working_tree_score =
                    M.options.status_priority[existing_entry.working_tree]
                if working_tree_score > existing_working_tree_score then
                    existing_entry.working_tree = working_tree
                end
            end
        end
    end

    return statuses, summary
end

---Create the status ext_marks for the current buffer
---@param status table<string, oil_git_signs.EntryStatus?>
---@param buffer integer
---@param namespace integer
local function update_status_ext_marks(status, buffer, namespace)
    for line_nr = 1, vim.api.nvim_buf_line_count(buffer) do
        local entry = require("oil").get_entry_on_line(buffer, line_nr)

        if entry ~= nil then
            local git_status = status[entry.name]

            if git_status ~= nil then
                if M.options.show_index(entry.name, git_status.index) then
                    local index_display = M.options.index[git_status.index]

                    vim.api.nvim_buf_set_extmark(buffer, namespace, line_nr - 1, 0, {
                        sign_text = index_display.icon,
                        sign_hl_group = index_display.hl_group,
                        priority = 1,
                    })
                end

                if M.options.show_working_tree(entry.name, git_status.working_tree) then
                    local working_tree_display = M.options.working_tree[git_status.working_tree]

                    vim.api.nvim_buf_set_extmark(buffer, namespace, line_nr - 1, 1, {
                        sign_text = working_tree_display.icon,
                        sign_hl_group = working_tree_display.hl_group,
                        priority = 1,
                    })
                end
            end
        end
    end
end

---Generate a augroup for a buffer and return it
---@param buffer integer buf_nr
---@return integer aug_id
local function buf_get_augroup(buffer)
    return vim.api.nvim_create_augroup(("OilGitSigns_buf-%d"):format(buffer), {})
end

---Generate a namespace for a buffer and return it
---@param buffer integer buf_nr
---@return integer ns_id
local function buf_get_namespace(buffer)
    return vim.api.nvim_create_namespace(("OilGitSigns_buf-%d"):format(buffer))
end

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
        vim.notify("OilGitSigns: not a git repository", vim.log.levels.ERROR)
        return
    end

    if count == 0 then
        return
    end

    count = count or 1
    ---@type { index: oil_git_signs.GitStatus[], working_tree: oil_git_signs.GitStatus[] }
    statuses = statuses or { index = M.GitStatus, working_tree = M.GitStatus }

    local icons = { ---@type { [0]: string[], [1]: string[] }
        [0] = vim.tbl_map(function(status)
            return M.options.index[status].icon
        end, statuses.index),
        [1] = vim.tbl_map(function(status)
            return M.options.working_tree[status].icon
        end, statuses.working_tree),
    }

    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local namespace = buf_get_namespace(buf)

    local extmark_items = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })

    if count < 0 then
        if direction == "down" then
            extmark_items = vim.fn.reverse(extmark_items)
        end

        count = math.abs(count)
    elseif direction == "up" then
        extmark_items = vim.fn.reverse(extmark_items)
    end

    local _, cur_cursor_row, _, _ = unpack(vim.fn.getpos("."))

    -- since it is possible to dynamically disable our extmarks we can only reliably decrement
    -- the count based on what row we are on instead of going based off of the iterations
    local last_row = nil

    for _, extmark_item in ipairs(extmark_items) do
        ---@diagnostic disable-next-line: assign-type-mismatch
        local _ = extmark_items[1] ---@type integer extmark_id
        local row = extmark_item[2] + 1 ---@type integer row (zero indexed)
        ---@diagnostic disable-next-line: assign-type-mismatch
        local col = extmark_item[3] ---@type integer col
        local details = assert(extmark_item[4]) ---@type vim.api.keyset.extmark_details
        local sign_text = assert(details.sign_text)

        if
            (direction == "up" and row < cur_cursor_row)
            or (direction == "down" and row > cur_cursor_row)
        then
            if vim.tbl_contains(icons[col], sign_text:sub(1, 1)) and row ~= last_row then
                last_row = row
                count = count - 1
            end

            if count == 0 then
                -- HACK: sometimes when really large dirs (>1k) are saved and this function is called
                -- to get the last row, `row` will be larger than the size of the buffer. Similarly
                -- when called to get the first row it will hang
                row = math.min(row, vim.api.nvim_buf_line_count(buf))

                vim.api.nvim_win_set_cursor(win, { row, 1 })
                return
            end
        end
    end

    vim.notify("OilGitSigns: no status to move to", vim.log.levels.WARN)
end

---Create the global default highlights
local function create_highlight_groups()
    vim.api.nvim_set_hl(0, "OilGitSignsIndexSubModModified", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexUnmodified", { link = "Normal" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexModified", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexTypeChanged", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexAdded", { link = "OilCreate" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexDeleted", { link = "OilDelete" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexRenamed", { link = "OilMove" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexCopied", { link = "OilCopy" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexUnmerged", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexUntracked", { link = "OilCreate" })
    vim.api.nvim_set_hl(0, "OilGitSignsIndexIgnored", { link = "NonText" })

    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeSubModModified", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeUnmodified", { link = "Normal" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeModified", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeTypeChanged", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeAdded", { link = "OilCreate" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeDeleted", { link = "OilDelete" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeRenamed", { link = "OilMove" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeCopied", { link = "OilCopy" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeUnmerged", { link = "OilChange" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeUntracked", { link = "OilCreate" })
    vim.api.nvim_set_hl(0, "OilGitSignsWorkingTreeIgnored", { link = "NonText" })
end

---@alias oil_git_signs.DisplayOption { icon: string, hl_group: string }

---@class oil_git_signs.Config
M.defaults = {
    -- used to control whether statuses for the index should be display on a per entry basis
    ---@type fun(entry_name: string, index_status: oil_git_signs.GitStatus): boolean
    show_index = function(_)
        return true
    end,
    -- used to control whether statuses for the working tree should be display on a per entry basis
    ---@type fun(entry_name: string, working_tree_status: oil_git_signs.GitStatus): boolean
    show_working_tree = function(_)
        return true
    end,
    -- used to control whether `git status` should be run with `--ignored`
    ---@type fun(oil_dir: string): boolean
    show_ignored = function(_)
        return true
    end,
    -- used to customize how ext marks are displayed for statuses in the index
    ---@type table<oil_git_signs.GitStatus, oil_git_signs.DisplayOption>
    index = {
        -- stylua: ignore start
        [M.GitStatus.SUB_MOD_MODIFIED] = { icon = "m", hl_group = "OilGitSignsIndexSubModModified" },
        [M.GitStatus.MODIFIED]         = { icon = "M", hl_group = "OilGitSignsIndexModified"       },
        [M.GitStatus.UNMODIFIED]       = { icon = " ", hl_group = "OilGitSignsIndexUnmodified"     },
        [M.GitStatus.TYPE_CHANGED]     = { icon = "T", hl_group = "OilGitSignsIndexTypeChanged"    },
        [M.GitStatus.ADDED]            = { icon = "A", hl_group = "OilGitSignsIndexAdded"          },
        [M.GitStatus.DELETED]          = { icon = "D", hl_group = "OilGitSignsIndexDeleted"        },
        [M.GitStatus.RENAMED]          = { icon = "R", hl_group = "OilGitSignsIndexRenamed"        },
        [M.GitStatus.COPIED]           = { icon = "C", hl_group = "OilGitSignsIndexCopied"         },
        [M.GitStatus.UNMERGED]         = { icon = "U", hl_group = "OilGitSignsIndexUnmerged"       },
        [M.GitStatus.UNTRACKED]        = { icon = "?", hl_group = "OilGitSignsIndexUntracked"      },
        [M.GitStatus.IGNORED]          = { icon = "!", hl_group = "OilGitSignsIndexIgnored"        },
        -- stylua: ignore end
    },
    -- used to customize how ext marks are displayed for statuses in the working tree
    ---@type table<oil_git_signs.GitStatus, oil_git_signs.DisplayOption>
    working_tree = {
        -- stylua: ignore start
        [M.GitStatus.SUB_MOD_MODIFIED] = { icon = "m", hl_group = "OilGitSignsWorkingTreeSubModModified" },
        [M.GitStatus.MODIFIED]         = { icon = "M", hl_group = "OilGitSignsWorkingTreeModified"       },
        [M.GitStatus.UNMODIFIED]       = { icon = " ", hl_group = "OilGitSignsWorkingTreeUnmodified"     },
        [M.GitStatus.TYPE_CHANGED]     = { icon = "T", hl_group = "OilGitSignsWorkingTreeTypeChanged"    },
        [M.GitStatus.ADDED]            = { icon = "A", hl_group = "OilGitSignsWorkingTreeAdded"          },
        [M.GitStatus.DELETED]          = { icon = "D", hl_group = "OilGitSignsWorkingTreeDeleted"        },
        [M.GitStatus.RENAMED]          = { icon = "R", hl_group = "OilGitSignsWorkingTreeRenamed"        },
        [M.GitStatus.COPIED]           = { icon = "C", hl_group = "OilGitSignsWorkingTreeCopied"         },
        [M.GitStatus.UNMERGED]         = { icon = "U", hl_group = "OilGitSignsWorkingTreeUnmerged"       },
        [M.GitStatus.UNTRACKED]        = { icon = "?", hl_group = "OilGitSignsWorkingTreeUntracked"      },
        [M.GitStatus.IGNORED]          = { icon = "!", hl_group = "OilGitSignsWorkingTreeIgnored"        },
        -- stylua: ignore end
    },
    -- used to determine the most important status to display in the case where a subdir has
    -- multiple objects with unique statuses
    ---@type table<oil_git_signs.GitStatus, integer>
    status_priority = {
        -- stylua: ignore start
        [M.GitStatus.UNMERGED]         = 10,
        [M.GitStatus.MODIFIED]         = 9,
        [M.GitStatus.SUB_MOD_MODIFIED] = 8,
        [M.GitStatus.ADDED]            = 7,
        [M.GitStatus.DELETED]          = 6,
        [M.GitStatus.RENAMED]          = 5,
        [M.GitStatus.COPIED]           = 4,
        [M.GitStatus.TYPE_CHANGED]     = 3,
        [M.GitStatus.UNTRACKED]        = 2,
        [M.GitStatus.IGNORED]          = 1,
        [M.GitStatus.UNMODIFIED]       = 0,
        -- stylua: ignore end
    },
    -- used when creating the summary
    ---@type table<oil_git_signs.GitStatus, "added"|"removed"|"modified"|nil>
    status_classification = {
        -- stylua: ignore start
        [M.GitStatus.SUB_MOD_MODIFIED] = "modified",
        [M.GitStatus.UNMERGED]         = "modified",
        [M.GitStatus.MODIFIED]         = "modified",
        [M.GitStatus.ADDED]            = "added",
        [M.GitStatus.DELETED]          = "removed",
        [M.GitStatus.RENAMED]          = "modified",
        [M.GitStatus.COPIED]           = "added",
        [M.GitStatus.TYPE_CHANGED]     = "modified",
        [M.GitStatus.UNTRACKED]        = "added",
        [M.GitStatus.UNMODIFIED]       = nil,
        [M.GitStatus.IGNORED]          = nil,
        -- stylua: ignore end
    },
    -- used to create buffer local keymaps when oil-git-signs attaches to a buffer 
    -- note: the buffer option will always be overwritten
    ---@type { [1]: string|string[], [2]: string, [3]: string|function, [4]: vim.keymap.set.Opts? }[]
    keymaps = {},
}

---@type oil_git_signs.Config
M.options = nil

---@class oil_git_signs.AutoCmdEvent
---@field id integer autocommand id
---@field event string name of the triggered event
---@field group integer? autocommand group id, if any
---@field match string expanded value of `<amatch>`
---@field buf integer expanded value of `<abuf>`
---@field file string expanded value of `<afile>`
---@field data any arbitrary data passed from `vim.api.nvim_exec_autocmds`

---@param opts oil_git_signs.Config?
function M.setup(opts)
    if not vim.fn.executable("git") then
        return
    end

    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

    vim.schedule(create_highlight_groups)

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "oil",
        group = vim.api.nvim_create_augroup("OilGitSigns", {}),
        ---@param evt oil_git_signs.AutoCmdEvent
        callback = function(evt)
            if vim.b[evt.buf].oil_git_signs_exists then
                return
            end

            local path = require("oil").get_current_dir(evt.buf)
            -- need extra check in case path isn't actually present in the fs
            -- e.g. when entering a dir that has yet to have been created with `:w`
            if path == nil or vim.fn.isdirectory(path) == 0 then
                return
            end

            local git_root = require("oil.git").get_root(path)
            if git_root == nil then
                return
            end

            vim.b[evt.buf].oil_git_signs_exists = true

            for _, keymap in ipairs(M.options.keymaps) do
                keymap[4] = vim.tbl_deep_extend("force", keymap[4] or {}, { buffer = evt.buf })
                vim.keymap.set(unpack(keymap))
            end

            local current_status = nil
            local current_summary = nil

            local namespace = buf_get_namespace(evt.buf)
            local augroup = buf_get_augroup(evt.buf)

            -- only update ext_marks after oil has finished mutation or it has entered
            vim.api.nvim_create_autocmd("User", {
                pattern = "OilEnter",
                group = augroup,
                callback = vim.schedule_wrap(function()
                    current_status, current_summary = query_git_status(path)
                    vim.b[evt.buf].oil_git_signs_summary = current_summary

                    update_status_ext_marks(current_status, evt.buf, namespace)
                end),
            })
            vim.api.nvim_create_autocmd("User", {
                pattern = "OilMutationComplete",
                group = augroup,
                callback = vim.schedule_wrap(function()
                    current_status, current_summary = query_git_status(path)
                    vim.b[evt.buf].oil_git_signs_summary = current_summary

                    update_status_ext_marks(current_status, evt.buf, namespace)
                end),
            })

            -- make sure to clean up auto commands when oil deletes the buffer
            vim.api.nvim_create_autocmd("BufWipeout", {
                buffer = evt.buf,
                once = true,
                callback = vim.schedule_wrap(function()
                    vim.api.nvim_del_augroup_by_id(augroup)
                end),
            })
        end,
    })
end

return M
