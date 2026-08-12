if not vim.g.oil_git_signs_setup then
    return
end

require("oil-git-signs.autocmds").buf_init_autocmds(vim.api.nvim_get_current_buf())
