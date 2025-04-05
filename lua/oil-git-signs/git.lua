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
M.AllStatuses = vim.iter(M.GitStatus)
    :map(function(_, v)
        return v
    end)
    :totable()

---@class oil_git_signs.EntryStatus
---@field index oil_git_signs.GitStatus
---@field working_tree oil_git_signs.GitStatus

---@class oil_git_signs.StatusSummary
---@field index { added: integer, removed: integer, modified: integer }
---@field working_tree { added: integer, removed: integer, modified: integer }

---@class oil_git_signs.RepoStatus
---@field summary oil_git_signs.StatusSummary
---@field status table<string, oil_git_signs.EntryStatus?>

---@alias oil_git_signs.RepoStatusCache table<string, oil_git_signs.RepoStatus?>

---Table that maps a full path to a repo root (parent dir of .git) to a table that maps a full path of a file to a EntryStatus
---@type oil_git_signs.RepoStatusCache
M.RepoStatusCache = {}

---Table that maps a full path to a repo root (parent dir of .git) to a boolean of whether that repo's status is being queried
---@type table<string, boolean>
M.RepoBeingQueried = {}

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
---@return string path
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

    return path, index, working_tree
end

---Resolve status collision
---@param existing_status oil_git_signs.EntryStatus?
---@param new_status oil_git_signs.EntryStatus
---@return oil_git_signs.EntryStatus
local function resolve_collision(existing_status, new_status)
    local result

    if existing_status == nil then
        -- no collision
        result = vim.deepcopy(new_status)
    else
        result = vim.deepcopy(existing_status)

        -- resolve index collision
        local index_score = config.options.status_priority[new_status.index]
        local existing_index_score = config.options.status_priority[existing_status.index]
        if index_score > existing_index_score then
            result.index = new_status.index
        end

        -- resolve working tree collision
        local working_tree_score = config.options.status_priority[new_status.working_tree]
        local existing_working_tree_score =
            config.options.status_priority[existing_status.working_tree]
        if working_tree_score > existing_working_tree_score then
            result.working_tree = new_status.working_tree
        end
    end

    return result
end

---Get the git status for all of the items in repo
---@param repo_root string
---@param on_completetion fun(status: table<string, oil_git_signs.EntryStatus?>, summary: oil_git_signs.StatusSummary)
function M.query_git_status(repo_root, on_completetion)
    local status = {} ---@type table<string, oil_git_signs.EntryStatus?>
    local summary = new_summary()

    if vim.fn.isdirectory(repo_root) == 0 then
        on_completetion(status, summary)
    end

    -- could use `--porcelain` here for guaranteed compatibility, but parsing it is more diffciult
    -- due to it not being reported as a path relative the the cwd
    local cmd = { "git", "-c", "status.relativePaths=false", "status", "--short" }

    if config.options.show_ignored(repo_root) then
        table.insert(cmd, "--ignored")
    end

    table.insert(cmd, repo_root)

    M.RepoBeingQueried[repo_root] = true
    vim.system(cmd, { text = true, cwd = repo_root }, function(out)
        if out.code == 0 then
            assert(out.stdout ~= nil, "stdout is missing after querying status")

            for line in vim.gsplit(out.stdout, "\n") do
                if line ~= "" then
                    local path, index, working_tree = parse_git_status(line)
                    local fullpath = repo_root .. "/" .. path:gsub("/$", "")

                    -- update index summary
                    local index_status_class = config.options.status_classification[index]
                    if index_status_class then
                        local count = summary.index[index_status_class]
                        summary.index[index_status_class] = count + 1
                    end

                    -- update working tree summary
                    local working_tree_status_class =
                        config.options.status_classification[working_tree]
                    if working_tree_status_class then
                        local count = summary.working_tree[working_tree_status_class]
                        summary.working_tree[working_tree_status_class] = count + 1
                    end

                    local new_status = { index = index, working_tree = working_tree }
                    status[fullpath] = new_status

                    -- When multiple items in a sub directory have git statuses we need to decide
                    -- which status should be displayed when viewed from the parent directory.
                    -- And if this occurs in a nested directory than this status needs to
                    -- propagate recursively to all parents.

                    local prev_status = new_status
                    local start_path = fullpath
                    for dir in vim.fs.parents(start_path) do
                        if dir == repo_root or vim.fs.dirname(start_path) == repo_root then
                            break
                        end

                        local existing_status = status[dir]
                        local resolved_status = resolve_collision(existing_status, prev_status)

                        prev_status = resolved_status
                        status[dir] = resolved_status
                    end
                end
            end
        end

        M.RepoBeingQueried[repo_root] = false
        on_completetion(status, summary)
    end)
end

---Perform the staging operation on the entries from the 1 indexed exclusive range `start` to `stop`.
---@param paths string[]
---@param git_root string
---@param cb fun(out: vim.SystemCompleted)
function M.stage_files(paths, git_root, cb)
    vim.system({ "git", "add", unpack(paths) }, { text = true, cwd = git_root }, cb)
end

---Perform the unstaging operation on the entries from the 1 indexed exclusive range `start` to `stop`.
---@param paths string[]
---@param git_root string
---@param cb fun(out: vim.SystemCompleted)
function M.unstage_files(paths, git_root, cb)
    vim.system({ "git", "restore", "--staged", unpack(paths) }, { text = true, cwd = git_root }, cb)
end

---Get the git root of a path.
---@type fun(path: string): string?
M.get_root = utils.memoize(require("oil.git").get_root)

return M
