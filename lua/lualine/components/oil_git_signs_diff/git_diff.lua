---Much of the code here as been taken/reused from lualine itself.
---See the original source at: https://github.com/nvim-lualine/lualine.nvim/tree/afece9bbf960f908cbaffebaa4b5a0506e9dc8ed/lua/lualine/components/diff/git_diff.lua

local M = {}

---@class oil_git_signs.LualineConfig
local defaults = {
    diff = {
        ---@type ("added" | "modified" | "removed")[]
        index = { "added", "modified", "removed" },
        ---@type ("added" | "modified" | "removed")[]
        working_tree = { "added", "modified", "removed" },
    },
}

---@type oil_git_signs.LualineConfig
local config = nil

---initialize the module
---@param opts table
function M.init(opts)
    config = vim.tbl_deep_extend("force", defaults, opts or {})
end

---Api to get git sign count
---scheme :
---{
---   added = added_count,
---   modified = modified_count,
---   removed = removed_count,
---}
---@param bufnr integer?
---@return oil_git_signs.StatusSummary|nil
function M.get_sign_count(bufnr)
    if bufnr == nil or not vim.b[bufnr].oil_git_signs_exists then
        return nil
    end

    local stats = vim.b[bufnr].oil_git_signs_summary ---@type oil_git_signs.StatusSummary?

    if stats == nil then
        return nil
    end

    local results = { added = 0, modified = 0, removed = 0 }

    for _, diff_type in ipairs(config.diff.index) do
        results[diff_type] = results[diff_type] + stats.index[diff_type]
    end

    for _, diff_type in ipairs(config.diff.working_tree) do
        results[diff_type] = results[diff_type] + stats.working_tree[diff_type]
    end

    return results
end

return M
