local M = {}

local config = require("oil-git-signs.config")
local utils = require("oil-git-signs.utils")

local unpack = unpack or table.unpack

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
        pattern = '^.. "?.-"? -> "?(.-)"?$'
    else
        pattern = '^.. "?(.-)"?$'
    end

    -- extract the file path from the status
    local path = assert(raw_status:match(pattern), "failed to extract path from status") ---@type string

    -- extract the oil entry by taking everything up to first seperator
    local entry = assert(path:match("^([^/]+)"), "failed to extract entry from path") ---@type string

    return entry, index, working_tree
end

---Get the git status for items in a given directory
---@param path string
---@return table<string, oil_git_signs.EntryStatus?>
---@return oil_git_signs.StatusSummary
function M.query_git_status(path)
    local statuses = {} ---@type table<string, oil_git_signs.EntryStatus?>
    local summary = new_summary()

    if vim.fn.isdirectory(path) == 0 then
        return statuses, summary
    end

    -- could use `--porcelain` here for guaranteed compatibility, but parsing it is more diffciult
    -- due to it not being reported as a path relative the the cwd
    local cmd = { "git", "-c", "status.relativePaths=true", "status", "--short" }

    if config.options.show_ignored(path) then
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
            local index_status_class = config.options.status_classification[index]
            if index_status_class then
                local count = summary.index[index_status_class]
                summary.index[index_status_class] = count + 1
            end

            -- update working tree summary
            local working_tree_status_class = config.options.status_classification[working_tree]
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
                local index_score = config.options.status_priority[index]
                local existing_index_score = config.options.status_priority[existing_entry.index]
                if index_score > existing_index_score then
                    existing_entry.index = index
                end

                -- resolve working tree collision
                local working_tree_score = config.options.status_priority[working_tree]
                local existing_working_tree_score =
                    config.options.status_priority[existing_entry.working_tree]
                if working_tree_score > existing_working_tree_score then
                    existing_entry.working_tree = working_tree
                end
            end
        end
    end

    return statuses, summary
end

---Perform the staging operation on the entries from the 1 indexed exclusive range `start` to `stop`.
---@param paths string[]
---@param cb fun(out: vim.SystemCompleted)
function M.stage_files(paths, cb)
    vim.system({ "git", "add", unpack(paths) }, { text = true }, cb)
end

---Perform the unstaging operation on the entries from the 1 indexed exclusive range `start` to `stop`.
---@param paths string[]
---@param cb fun(out: vim.SystemCompleted)
function M.unstage_files(paths, cb)
    vim.system({ "git", "restore", "--staged", unpack(paths) }, { text = true }, cb)
end

---Get the git root of a path.
---@type fun(path: string): string?
M.get_root = utils.memoize(require("oil.git").get_root)

return M
