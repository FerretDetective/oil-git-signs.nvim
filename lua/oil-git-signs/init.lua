local utils = require("oil-git-signs.utils")
local require = utils.lazy_require

local FsWatcher = require("oil-git-signs.watcher")
local api = require("oil-git-signs.api")
local config = require("oil-git-signs.config")
local extmarks = require("oil-git-signs.extmarks")
local git = require("oil-git-signs.git")

local unpack = unpack or table.unpack

local M = {}

---@class oil_git_signs.AutoCmdEvent
---@field id integer autocommand id
---@field event string name of the triggered event
---@field group integer? autocommand group id, if any
---@field match string expanded value of `<amatch>`
---@field buf integer expanded value of `<abuf>`
---@field file string expanded value of `<afile>`
---@field data any arbitrary data passed from `vim.api.nvim_exec_autocmds`

---Keep track of whether an fs watcher already exists for a given repo
---@type table<string, oil_git_signs.FsWatcher?>
local RepoWatcherExists = {}

---Keep track of the number of attached clients for a given repo
---@type table<string, integer?>
local RepoAttachedCount = {}

---@param evt oil_git_signs.AutoCmdEvent
local function set_autocmds(evt)
    local buf = evt.buf

    if vim.b[buf].oil_git_signs_exists then
        return
    end

    local path = require("oil").get_current_dir(buf)
    -- need extra check in case path isn't actually present in the fs
    -- e.g. when entering a dir that has yet to have been created with `:w`
    if path == nil or vim.fn.isdirectory(path) == 0 then
        return
    end

    local repo_root = git.get_root(path)
    if repo_root == nil then
        return
    end

    vim.b[buf].oil_git_signs_exists = true

    local repo_attached_count = RepoAttachedCount[repo_root]
    if repo_attached_count == nil then
        repo_attached_count = 1
    else
        repo_attached_count = repo_attached_count + 1
    end
    RepoAttachedCount[repo_root] = repo_attached_count

    for _, keymap in ipairs(M.options.keymaps) do
        keymap[4] = vim.tbl_deep_extend("force", keymap[4] or {}, { buffer = buf })
        vim.keymap.set(unpack(keymap))
    end

    local namespace = utils.buf_get_namespace(buf)
    local augroup = utils.buf_get_augroup(buf)

    -- query initial git status
    git.query_git_status(repo_root, function(status, summary)
        git.RepoStatusCache[repo_root] = { status = status, summary = summary }
    end)

    -- only create one set of watcher/autocmd per repo
    if not RepoWatcherExists[repo_root] then
        local do_update = function()
            if git.RepoBeingQueried[repo_root] then
                return
            end

            git.query_git_status(repo_root, function(status, summary)
                git.RepoStatusCache[repo_root] = { status = status, summary = summary }

                vim.schedule(function()
                    vim.api.nvim_exec_autocmds("User", { pattern = "OilGitSignsRefreshExtmarks" })
                end)
            end)
        end

        local watcher = FsWatcher.new(string.format("%s/.git/index", repo_root))
        watcher:register_callback(function(_, _, events)
            if not events.change then
                return
            end

            do_update()
        end)
        watcher:start()
        RepoWatcherExists[repo_root] = watcher

        vim.api.nvim_create_autocmd("User", {
            pattern = "OilMutationComplete",
            ---@param event oil_git_signs.AutoCmdEvent
            callback = function(event)
                local buf_name = vim.api.nvim_buf_get_name(event.buf)
                local _, event_path = require("oil.util").parse_url(buf_name)
                local event_root = git.get_root(assert(event_path))

                if event_root ~= repo_root then
                    return
                end

                do_update()
            end,
        })
    end

    ---@param event oil_git_signs.AutoCmdEvent
    local refresh_extmarks = vim.schedule_wrap(function(event)
        if vim.bo[event.buf].filetype ~= "oil" then
            return
        end

        local status = git.RepoStatusCache[repo_root]

        if status == nil then
            utils.error(string.format("RepoStatusCache is empty for %s/.git", repo_root))
            return
        end

        extmarks.update_status_ext_marks(
            status.status,
            buf,
            namespace,
            1,
            vim.api.nvim_buf_line_count(buf)
        )
        vim.b[buf].oil_git_signs_summary = status.summary
    end)

    -- update extmarks when we are requested or when we enter a new buffer
    vim.api.nvim_create_autocmd("User", {
        pattern = { "OilGitSignsRefreshExtmarks" },
        desc = "update oil git signs extmarks",
        group = augroup,
        callback = refresh_extmarks,
    })
    vim.api.nvim_create_autocmd("BufModifiedSet", {
        desc = "update oil git signs extmarks",
        pattern = "*",
        group = augroup,
        callback = function()
            vim.api.nvim_exec_autocmds("User", { pattern = "OilGitSignsRefreshExtmarks" })
        end,
    })

    -- make sure to clean up auto commands when oil deletes the buffer
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = buf,
        desc = "cleanup oil-git-signs autocmds when oil unloads the buf",
        once = true,
        callback = vim.schedule_wrap(function()
            vim.api.nvim_del_augroup_by_id(augroup)
            local ref_count = RepoAttachedCount[repo_root] - 1
            RepoAttachedCount[repo_root] = ref_count

            --- no other clients are active in this repo
            if ref_count then
                git.RepoStatusCache[repo_root] = nil

                assert(RepoWatcherExists[repo_root]):stop()
                RepoWatcherExists[repo_root] = nil
            end

        end),
    })
end

---@param opts oil_git_signs.Config?
function M.setup(opts)
    if vim.fn.executable("git") == 0 then
        utils.error("no executable git detected")
        return
    end

    if vim.fn.has("nvim-0.10") == 0 then
        utils.error("minimum required neovim version is 0.10.0")
        return
    end

    M.GitStatus = git.GitStatus
    M.AllStatuses = git.AllStatuses
    M.defaults = config.defaults
    M.jump_to_status = api.jump_to_status
    M.stage_selected = api.stage_selected
    M.unstage_selected = api.unstage_selected

    config.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
    M.options = config.options

    vim.schedule(function()
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
    end)

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "oil",
        desc = "main oil-git-signs trigger",
        group = vim.api.nvim_create_augroup("OilGitSigns", {}),
        callback = set_autocmds,
    })
end

return M
