---Much of the code here as been taken/reused from lualine itself.
---See the original source at: https://github.com/nvim-lualine/lualine.nvim/tree/afece9bbf960f908cbaffebaa4b5a0506e9dc8ed/lua/lualine/components/diff/init.lua

local lualine_require = require("lualine_require")
local modules = lualine_require.lazy_require({
    git_diff = "lualine.components.oil_git_signs_diff.git_diff",
    utils = "lualine.utils.utils",
    highlight = "lualine.highlight",
})
local M = lualine_require.require("lualine.component"):extend()

local default_options = {
    colored = true,
    symbols = { added = "+", modified = "~", removed = "-" },
}

local function apply_default_colors(opts)
    local default_diff_color = {
        added = {
            fg = modules.utils.extract_color_from_hllist(
                "fg",
                { "LuaLineDiffAdd", "GitSignsAdd", "GitGutterAdd", "DiffAdded", "DiffAdd" },
                "#90ee90"
            ),
        },
        modified = {
            fg = modules.utils.extract_color_from_hllist("fg", {
                "LuaLineDiffChange",
                "GitSignsChange",
                "GitGutterChange",
                "DiffChanged",
                "DiffChange",
            }, "#f0e130"),
        },
        removed = {
            fg = modules.utils.extract_color_from_hllist("fg", {
                "LuaLineDiffDelete",
                "GitSignsDelete",
                "GitGutterDelete",
                "DiffRemoved",
                "DiffDelete",
            }, "#ff0038"),
        },
    }

    opts.diff_color = vim.tbl_deep_extend("keep", opts.diff_color or {}, default_diff_color)
end

-- Initializer
function M:init(options)
    M.super.init(self, options)
    apply_default_colors(self.options)
    self.options = vim.tbl_deep_extend("keep", self.options or {}, default_options)

    -- create highlights and save highlight_name in highlights table
    if self.options.colored then
        self.highlights = {
            added = self:create_hl(self.options.diff_color.added, "added"),
            modified = self:create_hl(self.options.diff_color.modified, "modified"),
            removed = self:create_hl(self.options.diff_color.removed, "removed"),
        }
    end

    modules.git_diff.init(self.options)
end

-- Function that runs every time statusline is updated
function M:update_status(is_focused)
    local bufnr = nil
    if is_focused then
        bufnr = vim.api.nvim_get_current_buf()
    end

    local git_diff = modules.git_diff.get_sign_count(bufnr)

    if git_diff == nil then
        return ""
    end

    local colors = {}
    if self.options.colored then
        -- load the highlights and store them in colors table
        for name, highlight_name in pairs(self.highlights) do
            colors[name] = self:format_hl(highlight_name)
        end
    end

    local result = {}
    -- loop though data and load available sections in result table
    for _, name in ipairs({ "added", "modified", "removed" }) do
        if git_diff[name] and git_diff[name] > 0 then
            if self.options.colored then
                table.insert(result, colors[name] .. self.options.symbols[name] .. git_diff[name])
            else
                table.insert(result, self.options.symbols[name] .. git_diff[name])
            end
        end
    end

    if #result > 0 then
        return table.concat(result, " ")
    end

    return ""
end

return M
