local M = {}

---@type oil_git_signs.GitStatus
local GitStatus = {
    -- stylua: ignore start
    SUB_MOD_MODIFIED = "m",
    UNMODIFIED       = " ",
    MODIFIED         = "M",
    TYPE_CHANGED     = "T",
    ADDED            = "A",
    DELETED          = "D",
    RENAMED          = "R",
    COPIED           = "C",
    UNMERGED         = "U",
    UNTRACKED        = "?",
    IGNORED          = "!",
    -- stylua: ignore end
}

---@alias oil_git_signs.DisplayOption { icon: string, hl_group: string }

---@class oil_git_signs.Config
M.defaults = {
    -- show a confirm message when performing any git operations
    ---@type boolean|fun(paths: string[]): boolean
    confirm_git_operations = true,
    -- don't show a confirm message for simple git operations
    -- by default a simple git operation is definied as one of the following:
    --     - no more than 5 git stages
    --     - no more than 5 git unstages
    skip_confirm_for_simple_git_operations = false,
    -- used to define what the max number of git operations will be considered simple
    -- note that is this only relevant when `skip_confirm_for_simple_git_operations` is enabled
    simple_git_operations = {
        max_stages = 5,
        max_unstages = 5,
    },
    -- used to control whether statuses for the index should be displayed on a per entry basis
    ---@type fun(entry_name: string, index_status: oil_git_signs.GitStatus): boolean
    show_index = function()
        return true
    end,
    -- used to control whether statuses for the working tree should be displayed on a per entry basis
    ---@type fun(entry_name: string, working_tree_status: oil_git_signs.GitStatus): boolean
    show_working_tree = function()
        return true
    end,
    -- used to control whether `git status` should be run with `--ignored`
    ---@type fun(oil_dir: string): boolean
    show_ignored = function()
        return true
    end,
    -- used to customize how ext marks are displayed for statuses in the index
    ---@type table<oil_git_signs.GitStatus, oil_git_signs.DisplayOption>
    index = {
        -- stylua: ignore start
        [GitStatus.SUB_MOD_MODIFIED] = { icon = "m", hl_group = "OilGitSignsIndexSubModModified" },
        [GitStatus.MODIFIED]         = { icon = "M", hl_group = "OilGitSignsIndexModified"       },
        [GitStatus.UNMODIFIED]       = { icon = " ", hl_group = "OilGitSignsIndexUnmodified"     },
        [GitStatus.TYPE_CHANGED]     = { icon = "T", hl_group = "OilGitSignsIndexTypeChanged"    },
        [GitStatus.ADDED]            = { icon = "A", hl_group = "OilGitSignsIndexAdded"          },
        [GitStatus.DELETED]          = { icon = "D", hl_group = "OilGitSignsIndexDeleted"        },
        [GitStatus.RENAMED]          = { icon = "R", hl_group = "OilGitSignsIndexRenamed"        },
        [GitStatus.COPIED]           = { icon = "C", hl_group = "OilGitSignsIndexCopied"         },
        [GitStatus.UNMERGED]         = { icon = "U", hl_group = "OilGitSignsIndexUnmerged"       },
        [GitStatus.UNTRACKED]        = { icon = "?", hl_group = "OilGitSignsIndexUntracked"      },
        [GitStatus.IGNORED]          = { icon = "!", hl_group = "OilGitSignsIndexIgnored"        },
        -- stylua: ignore end
    },
    -- used to customize how ext marks are displayed for statuses in the working tree
    ---@type table<oil_git_signs.GitStatus, oil_git_signs.DisplayOption>
    working_tree = {
        -- stylua: ignore start
        [GitStatus.SUB_MOD_MODIFIED] = { icon = "m", hl_group = "OilGitSignsWorkingTreeSubModModified" },
        [GitStatus.MODIFIED]         = { icon = "M", hl_group = "OilGitSignsWorkingTreeModified"       },
        [GitStatus.UNMODIFIED]       = { icon = " ", hl_group = "OilGitSignsWorkingTreeUnmodified"     },
        [GitStatus.TYPE_CHANGED]     = { icon = "T", hl_group = "OilGitSignsWorkingTreeTypeChanged"    },
        [GitStatus.ADDED]            = { icon = "A", hl_group = "OilGitSignsWorkingTreeAdded"          },
        [GitStatus.DELETED]          = { icon = "D", hl_group = "OilGitSignsWorkingTreeDeleted"        },
        [GitStatus.RENAMED]          = { icon = "R", hl_group = "OilGitSignsWorkingTreeRenamed"        },
        [GitStatus.COPIED]           = { icon = "C", hl_group = "OilGitSignsWorkingTreeCopied"         },
        [GitStatus.UNMERGED]         = { icon = "U", hl_group = "OilGitSignsWorkingTreeUnmerged"       },
        [GitStatus.UNTRACKED]        = { icon = "?", hl_group = "OilGitSignsWorkingTreeUntracked"      },
        [GitStatus.IGNORED]          = { icon = "!", hl_group = "OilGitSignsWorkingTreeIgnored"        },
        -- stylua: ignore end
    },
    -- used to determine the most important status to display in the case where a subdir has
    -- multiple objects with unique statuses
    ---@type table<oil_git_signs.GitStatus, integer>
    status_priority = {
        -- stylua: ignore start
        [GitStatus.UNMERGED]         = 10,
        [GitStatus.MODIFIED]         = 9,
        [GitStatus.SUB_MOD_MODIFIED] = 8,
        [GitStatus.ADDED]            = 7,
        [GitStatus.DELETED]          = 6,
        [GitStatus.RENAMED]          = 5,
        [GitStatus.COPIED]           = 4,
        [GitStatus.TYPE_CHANGED]     = 3,
        [GitStatus.UNTRACKED]        = 2,
        [GitStatus.IGNORED]          = 1,
        [GitStatus.UNMODIFIED]       = 0,
        -- stylua: ignore end
    },
    -- used when creating the summary to determine how to count each status type
    ---@type table<oil_git_signs.GitStatus, "added"|"removed"|"modified"|nil>
    status_classification = {
        -- stylua: ignore start
        [GitStatus.SUB_MOD_MODIFIED] = "modified",
        [GitStatus.UNMERGED]         = "modified",
        [GitStatus.MODIFIED]         = "modified",
        [GitStatus.ADDED]            = "added",
        [GitStatus.DELETED]          = "removed",
        [GitStatus.RENAMED]          = "modified",
        [GitStatus.COPIED]           = "added",
        [GitStatus.TYPE_CHANGED]     = "modified",
        [GitStatus.UNTRACKED]        = "added",
        [GitStatus.UNMODIFIED]       = nil,
        [GitStatus.IGNORED]          = nil,
        -- stylua: ignore end
    },
    -- used to create buffer local keymaps when oil-git-signs attaches to a buffer
    -- note: the buffer option will always be overwritten
    ---@type { [1]: string|string[], [2]: string, [3]: string|function, [4]: vim.keymap.set.Opts? }[]
    keymaps = {},
}

---@type oil_git_signs.Config
M.options = nil

return M
