local api = require("oil-git-signs.api")
local config = require("oil-git-signs.config")
local git = require("oil-git-signs.git")

local M = {}

M.GitStatus = git.GitStatus
M.AllStatuses = git.AllStatuses
M.defaults = config.defaults
M.jump_to_status = api.jump_to_status
M.stage_selected = api.stage_selected
M.unstage_selected = api.unstage_selected
M.refresh_git_status = api.refresh_git_status
M.setup = config.setup

return M
