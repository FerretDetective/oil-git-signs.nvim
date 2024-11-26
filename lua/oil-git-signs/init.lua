local M = {}

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
    local utils = require("oil-git-signs.utils")
    local api = require("oil-git-signs.api")
    local config = require("oil-git-signs.config")
    local extmarks = require("oil-git-signs.extmarks")
    local git = require("oil-git-signs.git")

    local unpack = unpack or table.unpack

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

            local git_root = git.get_root(path)
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

            local namespace = utils.buf_get_namespace(evt.buf)
            local augroup = utils.buf_get_augroup(evt.buf)

            ---@type fun(start: integer, stop: integer)
            local clear_extmarks = utils.apply_debounce(function(start, stop)
                vim.api.nvim_buf_clear_namespace(evt.buf, namespace, start, stop)
            end, 250)

            ---@type fun(e: oil_git_signs.AutoCmdEvent)
            local updater = utils.apply_debounce(function(e)
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

                current_status, current_summary = git.query_git_status(path)

                vim.b[evt.buf].oil_git_signs_summary = current_summary
                extmarks.update_status_ext_marks(current_status, evt.buf, namespace, 1, buf_len)
            end, 100)

            -- only update git status & ext_marks after oil has finished mutation, it has entered/reloaded,
            -- or when we need to refresh (e.g. after staging a file)
            vim.api.nvim_create_autocmd("User", {
                pattern = { "OilEnter", "OilMutationComplete" },
                desc = "link oil.nvim triggers to oil-git-signs triggers",
                group = augroup,
                callback = function()
                    vim.api.nvim_exec_autocmds("User", { pattern = "OilGitSignsRefresh" })
                end,
            })
            vim.api.nvim_create_autocmd("User", {
                pattern = "OilGitSignsRefresh",
                desc = "update git status & extmarks",
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
