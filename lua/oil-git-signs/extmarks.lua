local M = {}

local config = require("oil-git-signs.config")

---Create/update the status ext_marks for the current buffer
---@param status table<string, oil_git_signs.EntryStatus?>
---@param buffer integer buffer number
---@param namespace integer namespace id
---@param start integer 1 indexed start row
---@param stop integer 1 indexed stop row
function M.update_status_ext_marks(status, buffer, namespace, start, stop)
    local jump_list = {}

    for lnum = start, stop do
        local entry = require("oil").get_entry_on_line(buffer, lnum)
        if entry == nil then
            return
        end

        local git_status = status[entry.name]

        if git_status ~= nil then
            jump_list[lnum] = git_status.index .. git_status.working_tree

            if config.options.show_index(entry.name, git_status.index) then
                local index_display = config.options.index[git_status.index]

                vim.api.nvim_buf_set_extmark(buffer, namespace, lnum - 1, 0, {
                    invalidate = true,
                    sign_text = index_display.icon,
                    sign_hl_group = index_display.hl_group,
                    priority = 1,
                })
            end

            if config.options.show_working_tree(entry.name, git_status.working_tree) then
                local working_tree_display = config.options.working_tree[git_status.working_tree]

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

return M
