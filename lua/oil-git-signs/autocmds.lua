local FsWatcher = require("oil-git-signs.watcher")
local api = require("oil-git-signs.api")
local config = require("oil-git-signs.config")
local git = require("oil-git-signs.git")
local oil = require("oil")
local oil_util = require("oil.util")
local utils = require("oil-git-signs.utils")
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

---Keep track the `FSWatcher` for each repository
---@type table<string, oil_git_signs.FsWatcher?>
M.RepoWatcherList = {}

---Keep track of the number of attached clients for a given repo
---@type table<string, integer?>
M.RepoAttachedCount = {}

---@param evt oil_git_signs.AutoCmdEvent
function M.buf_init_autocmds(evt)
    local buf = evt.buf

    if vim.b[buf].oil_git_signs_exists then
        return
    end

    if not config.options.should_attach(buf) then
        return
    end

    local path = oil.get_current_dir(buf)
    -- need extra check in case path isn't actually present in the fs
    -- e.g. when entering a dir that has yet to have been created with `:w`
    if path == nil or vim.fn.isdirectory(path) == 0 then
        return
    end

    local repo_root = git.get_root(path)
    if repo_root == nil then
        return
    end

    for _, keymap in ipairs(config.options.keymaps) do
        keymap[4] = vim.tbl_deep_extend("force", keymap[4] or {}, { buffer = buf })
        vim.keymap.set(unpack(keymap))
    end

    vim.api.nvim_create_autocmd("User", {
        pattern = "OilGitSignsQueryGitStatusDone",
        ---@param event oil_git_signs.AutoCmdEvent
        callback = function(event)
            if event.data["repo_root_path"] ~= repo_root or event.buf ~= buf then
                return
            end

            vim.cmd("redraw!")

            local repo_status = git.RepoStatusCache[repo_root]
            if repo_status then
                vim.b[buf].oil_git_signs_summary = repo_status.summary
            end
        end,
    })

    -- make sure to clean up auto commands when oil deletes the buffer
    vim.api.nvim_create_autocmd("BufWipeout", {
        desc = "cleanup oil-git-signs autocmds when oil unloads the buf",
        buffer = buf,
        once = true,
        callback = vim.schedule_wrap(function()
            pcall(vim.api.nvim_del_augroup_by_name, utils.buf_get_augroup_name(buf))
            local ref_count = math.max(M.RepoAttachedCount[repo_root] - 1, 0)
            M.RepoAttachedCount[repo_root] = ref_count

            --- no other clients are active in this repo
            if ref_count == 0 then
                pcall(vim.api.nvim_del_augroup_by_name, utils.repo_get_augroup_name(repo_root))
                git.RepoStatusCache[repo_root] = nil

                assert(M.RepoWatcherList[repo_root], "FSWatcher is missing"):stop()
                M.RepoWatcherList[repo_root] = nil
                git.RepoStatusCache[repo_root] = nil
            end
        end),
    })

    local cur_ref_count = M.RepoAttachedCount[repo_root] or 0

    -- initial setup for first attachment to a repository
    if cur_ref_count == 0 then
        local repo_watcher_augroup = utils.repo_get_augroup(repo_root)

        vim.api.nvim_create_autocmd("User", {
            pattern = "OilGitSignsQueryGitStatus",
            group = repo_watcher_augroup,
            ---@type fun(event: oil_git_signs.AutoCmdEvent)
            callback = function(event)
                local repo = event.data["repo_root_path"]

                if type(repo) ~= "string" then
                    utils.error("cannot query git status, no repo specified")
                    return
                end

                if M.RepoAttachedCount[repo] == 0 then
                    utils.error("cannot query git status, no oil bufs in the repo exist")
                    return
                end

                if git.RepoBeingQueried[repo_root] then
                    return
                end

                git.query_git_status(repo_root, function(status, summary)
                    git.RepoStatusCache[repo_root] = { status = status, summary = summary }
                    vim.schedule(function()
                        vim.api.nvim_exec_autocmds("User", {
                            pattern = "OilGitSignsQueryGitStatusDone",
                            data = { repo_root_path = repo },
                        })
                    end)
                end)
            end,
        })

        --TODO: The ideal solution would be to have two `FsWatcher`s.
        -- The first would recursively monitor the repo for changes to the working tree,
        -- and the other would monitor just the git index. Unfortunately libuv currently only
        -- supports recursive file change detection on OSX and Windows.
        local watcher = FsWatcher.new(string.format("%s/.git/index", repo_root))
        watcher:register_callback(function(_, _, events)
            if not events.change then
                return
            end

            api.refresh_git_status(repo_root)
        end)
        watcher:start()
        M.RepoWatcherList[repo_root] = watcher

        vim.api.nvim_create_autocmd("User", {
            pattern = "OilMutationComplete",
            group = repo_watcher_augroup,
            ---@param event oil_git_signs.AutoCmdEvent
            callback = function(event)
                local buf_name = vim.api.nvim_buf_get_name(event.buf)
                local _, event_path = oil_util.parse_url(buf_name)
                local event_root = git.get_root(assert(event_path, "could not parse oil url"))

                if event_root ~= repo_root then
                    return
                end

                api.refresh_git_status(repo_root)
            end,
        })

        api.refresh_git_status(repo_root)
    end

    M.RepoAttachedCount[repo_root] = cur_ref_count + 1
    vim.b[buf].oil_git_signs_exists = true
end

return M
