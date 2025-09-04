local api = require("oil-git-signs.api")
local autocmds = require("oil-git-signs.autocmds")
local config = require("oil-git-signs.config")
local extmarks = require("oil-git-signs.extmarks")
local git = require("oil-git-signs.git")
local utils = require("oil-git-signs.utils")

local M = {}

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
    M.refresh_git_status = api.refresh_git_status

    config.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
    M.options = config.options

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

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "oil",
        desc = "main oil-git-signs trigger",
        group = vim.api.nvim_create_augroup("OilGitSigns", {}),
        callback = autocmds.buf_init_autocmds,
    })
    extmarks.init_extmark_provider(vim.api.nvim_create_namespace("OilGitSignsDecorationsProvider"))

    -- The following is needed to prevent ogs from blocking oil.nvim's git based file operations
    local oil_git = require("oil.git")
    local old_rm, old_add, old_mv = oil_git.rm, oil_git.add, oil_git.mv

    ---@diagnostic disable-next-line: duplicate-set-field
    oil_git.rm = function(path, cb)
        if not vim.b.oil_git_signs_exists then
            return old_rm(path, cb)
        end

        local repo_root = assert(git.get_root(path), "ogs attached, but couldn't find git root")

        if
            vim.wait(1500, function()
                return not git.RepoBeingQueried[repo_root]
            end, 100)
        then
            return old_rm(path, cb)
        end
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    oil_git.add = function(path, cb)
        if not vim.b.oil_git_signs_exists then
            return old_add(path, cb)
        end

        local repo_root = assert(git.get_root(path), "ogs attached, but couldn't find git root")

        if
            vim.wait(1500, function()
                return not git.RepoBeingQueried[repo_root]
            end, 100)
        then
            return old_add(path, cb)
        end
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    oil_git.mv = function(entry_type, src_path, dest_path, cb)
        if not vim.b.oil_git_signs_exists then
            return old_mv(entry_type, src_path, dest_path, cb)
        end

        if
            vim.wait(1500, function()
                local src_root = git.get_root(src_path)
                local dest_root = git.get_root(dest_path)

                -- don't wait if the src/dest is not git tracked, or not being queried
                return (src_root == nil or not git.RepoBeingQueried[src_root])
                    and (dest_root == nil or not git.RepoBeingQueried[dest_root])
            end, 100)
        then
            return old_mv(entry_type, src_path, dest_path, cb)
        end
    end
end

return M
