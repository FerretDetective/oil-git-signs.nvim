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

---@type oil_git_signs.GitStatus[]
M.AllStatuses = { "m", " ", "M", "T", "A", "D", "R", "C", "U", "?", "!" }

---@class oil_git_signs.EntryStatus
---@field index oil_git_signs.GitStatus
---@field working_tree oil_git_signs.GitStatus

---@class oil_git_signs.StatusSummary
---@field index { added: integer, removed: integer, modified: integer }
---@field working_tree { added: integer, removed: integer, modified: integer }

---@alias oil_git_signs.JumpList (string|vim.NIL)[]

---Create a wrapper for a function which ensures that function is called at most every `time_ms` millis
---@param fn fun(...: any)
---@param time_ms integer
---@return fun(...: any)
local function apply_debounce(fn, time_ms)
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

    local pattern
    if index == M.GitStatus.RENAMED or working_tree == M.GitStatus.RENAMED then
        pattern = '.. "?.+"? -> ?(.+)"?$'
    else
        pattern = '.. "?(.+)"?$'
    end

    -- extract the filename/path
    local path = assert(raw_status:match(pattern), "failed to match git status") ---@type string

    -- extract the first part of the path (up to first sep)
    local entry = assert( ---@type string
        path:match(("^([^%s]+)"):format(require("oil.fs").sep)),
        "failed to extract entry path"
    )

    return entry, index, working_tree
end

---Get the git status for items in a given directory
---@param path string
---@return table<string, oil_git_signs.EntryStatus?>
---@return oil_git_signs.StatusSummary
local function query_git_status(path)
    local statuses = {} ---@type table<string, oil_git_signs.EntryStatus?>
    local summary = new_summary()

    if vim.fn.isdirectory(path) == 0 then
        return statuses, summary
    end

    -- could use `--porcelain` here for guaranteed compatibility, but parsing it is more diffciult
    -- due to it not being reported as a path relative the the cwd
    local cmd = { "git", "-c", "status.relativePaths=true", "status", "--short" }

    if M.options.show_ignored(path) then
        table.insert(cmd, "--ignored")
    end

    table.insert(cmd, ".")

    local task = vim.system(cmd, { text = true, cwd = path })
    local stdout = task:wait().stdout

    if stdout == nil then
        return statuses, summary
    end

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

---Create/update the status ext_marks for the current buffer
---@param status table<string, oil_git_signs.EntryStatus?>
---@param buffer integer buffer number
---@param namespace integer namespace id
---@param start integer 1 indexed start row
---@param stop integer 1 indexed stop row
local function update_status_ext_marks(status, buffer, namespace, start, stop)
    local jump_list = {}

    for lnum = start, stop do
        local entry = require("oil").get_entry_on_line(buffer, lnum)
        if entry == nil then
            return
        end

        local git_status = status[entry.name]

        if git_status ~= nil then
            jump_list[lnum] = git_status.index .. git_status.working_tree

            if M.options.show_index(entry.name, git_status.index) then
                local index_display = M.options.index[git_status.index]

                vim.api.nvim_buf_set_extmark(buffer, namespace, lnum - 1, 0, {
                    invalidate = true,
                    sign_text = index_display.icon,
                    sign_hl_group = index_display.hl_group,
                    priority = 1,
                })
            end

            if M.options.show_working_tree(entry.name, git_status.working_tree) then
                local working_tree_display = M.options.working_tree[git_status.working_tree]

                vim.api.nvim_buf_set_extmark(buffer, namespace, lnum - 1, 1, {
                    invalidate = true,
                    sign_text = working_tree_display.icon,
                    sign_hl_group = working_tree_display.hl_group,
                    priority = 1,
                })
            end
        else
            jump_list[lnum] = vim.NIL
        end
    end

    vim.b[buffer].oil_git_signs_jump_list = jump_list
end

---Generate an augroup for a given buffer
---@param buffer integer buf_nr
---@return integer aug_id
local function buf_get_augroup(buffer)
    return vim.api.nvim_create_augroup(("OilGitSigns_buf-%d"):format(buffer), {})
end

---Generate a namespace for a given buffer
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
    statuses = statuses or { index = M.AllStatuses, working_tree = M.AllStatuses }

    -- the strings are used to match against each status as `vim.tbl_contains` is more expensive
    local index_pattern = "^$"
    if #statuses.index > 0 then
        index_pattern = "[" .. table.concat(statuses.index, "") .. "]"
    end

    local working_tree_pattern = "^$"
    if #statuses.working_tree > 0 then
        working_tree_pattern = "[" .. table.concat(statuses.working_tree, "") .. "]"
    end

    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local buf_len = vim.api.nvim_buf_line_count(buf)
    local cursor_row = vim.api.nvim_win_get_cursor(win)[1]

    local start, stop, step
    if direction == "down" and count > 0 then
        -- start at the cursor and move down
        start = cursor_row + 1
        stop = buf_len
        step = 1
    elseif direction == "down" and count < 0 then
        -- start at the end and move up (e.g. getting the last status)
        start = buf_len
        stop = cursor_row
        step = -1
    elseif direction == "up" and count > 0 then
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

    -- count must be positive in order to be used to the determine how many statuses we need to visit
    count = math.abs(count)
    ---@type oil_git_signs.JumpList?
    local jump_list = vim.b[buf].oil_git_signs_jump_list

    if jump_list ~= nil and #jump_list == buf_len then
        for lnum = start, stop, step do
            local line_status = jump_list[lnum]

            if line_status ~= vim.NIL then
                if
                    ---@diagnostic disable-next-line: param-type-mismatch
                    line_status:sub(1, 1):match(index_pattern)
                    ---@diagnostic disable-next-line: param-type-mismatch
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

    vim.notify("OilGitSigns: no status valid to move to", vim.log.levels.WARN)
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
    -- used to control whether statuses for the index should be displayed on a per entry basis
    ---@type fun(entry_name: string, index_status: oil_git_signs.GitStatus): boolean
    show_index = function()
        return true
    end,
    -- used to control whether statuses for the working tree should be displayed on a per entry basis
    ---@type fun(entry_name: string, working_tree_status: oil_git_signs.GitStatus): boolean
    show_working_tree = function()
        return true
    end,
    -- used to control whether `git status` should be run with `--ignored`
    ---@type fun(oil_dir: string): boolean
    show_ignored = function()
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
    -- used when creating the summary to determine how to count each status type
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
    if vim.fn.executable("git") == 0 then
        vim.notify("OilGitSigns: no executable git detected", vim.log.levels.ERROR)
        return
    end

    if vim.fn.has("nvim-0.10") == 0 then
        vim.notify("OilGitSigns: minimum required neovim version is 0.10.0", vim.log.levels.ERROR)
        return
    end

    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

    vim.schedule(create_highlight_groups)

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "oil",
        desc = "main oil-git-signs trigger",
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

            ---@type fun(start: integer, stop: integer)
            local clear_extmarks = apply_debounce(function(start, stop)
                vim.api.nvim_buf_clear_namespace(evt.buf, namespace, start, stop)
            end, 250)

            ---@type fun(e: oil_git_signs.AutoCmdEvent)
            local updater = apply_debounce(function(e)
                -- don't refresh non-ogs bufs
                if not vim.b[e.buf].oil_git_signs_exists then
                    return
                end

                local buf_len = vim.api.nvim_buf_line_count(evt.buf)

                -- HACK: ?
                -- For a reason currently unknown to me, when reloading the buffer the namespaced
                -- extmarks would continue grow without bound. So this call ensures that there are
                -- only extmarks within the bounds of the buffer
                clear_extmarks(buf_len, -1)

                current_status, current_summary = query_git_status(path)

                vim.b[evt.buf].oil_git_signs_summary = current_summary
                update_status_ext_marks(current_status, evt.buf, namespace, 1, buf_len)
            end, 100)

            -- only update git status & ext_marks after oil has finished mutation or it has entered/reloaded
            vim.api.nvim_create_autocmd("User", {
                pattern = "OilEnter",
                desc = "update git status & extmarks on first load and refresh of oil buf",
                group = augroup,
                callback = updater,
            })
            vim.api.nvim_create_autocmd("User", {
                pattern = "OilMutationComplete",
                desc = "update git status & extmarks when oil mutates the fs",
                group = augroup,
                callback = updater,
            })

            -- make sure to clean up auto commands when oil deletes the buffer
            vim.api.nvim_create_autocmd("BufWipeout", {
                buffer = evt.buf,
                desc = "cleanup oil-git-signs autocmds when oil unloads the buf",
                once = true,
                callback = vim.schedule_wrap(function()
                    vim.api.nvim_del_augroup_by_id(augroup)
                end),
            })
        end,
    })
end

return M
