if vim.fn.executable("git") == 0 then
    require("oil-git-signs.utils").error("no executable git detected")
    return
end

if vim.fn.has("nvim-0.10") == 0 then
    require("oil-git-signs.utils").error("minimum required neovim version is 0.10.0")
    return
end

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

vim.api.nvim_set_decoration_provider(
    vim.api.nvim_create_namespace("OilGitSignsDecorationsProvider"),
    {
        on_win = function(_, _, bufnr, _, _)
            return vim.b[bufnr].oil_git_signs_exists
        end,
        on_line = function(_, _, bufnr, row)
            if not vim.b[bufnr].oil_git_signs_exists then
                return
            end

            local config = require("oil-git-signs.config")
            local git = require("oil-git-signs.git")
            local utils = require("oil-git-signs.utils")

            local oil_cwd = utils.get_oil_buf_path(bufnr)
            if oil_cwd == nil then
                utils.error(("failed to parse oil dir for buffer %d"):format(bufnr))
                return
            end

            local lnum = row + 1

            local entry = require("oil").get_entry_on_line(bufnr, lnum)
            if entry == nil then
                return
            end

            local entry_path = oil_cwd .. entry.name
            local repo_root = git.get_root(oil_cwd)

            if repo_root == nil then
                return
            end

            local repo_cache = git.RepoStatusCache[repo_root]

            if repo_cache == nil then
                return
            end

            local status = repo_cache.status[entry_path]

            if status == nil then
                return
            end

            local buf_ns = utils.buf_get_namespace(bufnr)

            if vim.fn.has("nvim-0.11") == 1 then
                if config.options.show_working_tree(entry.name, status.working_tree) then
                    local working_tree_display = config.options.working_tree[status.working_tree]

                    vim.api.nvim_buf_set_extmark(bufnr, buf_ns, row, 0, {
                        invalidate = true,
                        sign_text = working_tree_display.icon,
                        sign_hl_group = working_tree_display.hl_group,
                    })
                end

                if config.options.show_index(entry.name, status.index) then
                    local index_display = config.options.index[status.index]

                    vim.api.nvim_buf_set_extmark(bufnr, buf_ns, row, 0, {
                        invalidate = true,
                        sign_text = index_display.icon,
                        sign_hl_group = index_display.hl_group,
                    })
                end
            else
                if config.options.show_index(entry.name, status.index) then
                    local index_display = config.options.index[status.index]

                    vim.api.nvim_buf_set_extmark(bufnr, buf_ns, row, 0, {
                        invalidate = true,
                        sign_text = index_display.icon,
                        sign_hl_group = index_display.hl_group,
                    })
                end

                if config.options.show_working_tree(entry.name, status.working_tree) then
                    local working_tree_display = config.options.working_tree[status.working_tree]

                    vim.api.nvim_buf_set_extmark(bufnr, buf_ns, row, 0, {
                        invalidate = true,
                        sign_text = working_tree_display.icon,
                        sign_hl_group = working_tree_display.hl_group,
                    })
                end
            end
        end,
    }
)

-- The following is needed to prevent ogs from blocking oil.nvim's git based file operations
local oil_git = require("oil.git")
local old_rm, old_add, old_mv = oil_git.rm, oil_git.add, oil_git.mv

---@diagnostic disable-next-line: duplicate-set-field
oil_git.rm = function(path, cb)
    local git = require("oil-git-signs.git")
    local repo_root = git.get_root(path)

    if
        vim.wait(1500, function()
            return repo_root == nil or not git.RepoBeingQueried[repo_root]
        end, 100)
    then
        return old_rm(path, cb)
    end
end

---@diagnostic disable-next-line: duplicate-set-field
oil_git.add = function(path, cb)
    local git = require("oil-git-signs.git")
    local repo_root = git.get_root(path)

    if
        vim.wait(1500, function()
            return repo_root == nil or not git.RepoBeingQueried[repo_root]
        end, 100)
    then
        return old_add(path, cb)
    end
end

---@diagnostic disable-next-line: duplicate-set-field
oil_git.mv = function(entry_type, src_path, dest_path, cb)
    local git = require("oil-git-signs.git")

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

vim.g.oil_git_signs_setup = true
