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
end

return M
