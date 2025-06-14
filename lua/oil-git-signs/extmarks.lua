local M = {}

local config = require("oil-git-signs.config")
local git = require("oil-git-signs.git")
local utils = require("oil-git-signs.utils")

---Create the singular decorations provider for all oil_git_signs buffers
---@param namespace integer
function M.init_extmark_provider(namespace)
    vim.api.nvim_set_decoration_provider(namespace, {
        on_win = function(_, _, bufnr, _, _)
            return vim.b[bufnr].oil_git_signs_exists
        end,
        on_line = function(_, _, bufnr, row)
            if not vim.b[bufnr].oil_git_signs_exists then
                return
            end

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
    })
end

return M
