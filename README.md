# oil-git-signs.nvim

Add git information about your files when working with [oil.nvim](https://github.com/stevearc/oil.nvim).

![An image showcasing this plugin](https://repository-images.githubusercontent.com/857285568/ef99d858-08e4-480c-b4e7-495f2fab033f)

## Table of Contents
- [Requirements](#requirements)
- [Features](#features)
- [Installation](#installation)
- [Options](#options)
- [Recipes](#recipes)
- [API](#api)
- [Highlights](#highlights)
- [Bugs/Issues](#bugs-and-issues)
- [Contributing](#contributing)

## Features
- Display the git status of your files in oil.nvim as if you had run `git status --short`.
- Create keymaps to jump straight to files with a certain type of status.
- Stage and unstage files and directories within the oil buffer.
- Fine control over what highlights and icons to use for each type of status.
- Show status summaries on your statusline with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) integration.
- Very low impact on performance due to asynchronous processing.

## Requirements
- Neovim 0.10+
- oil.nvim
- Git

## Installation
I have only tested this plugin with lazy.nvim, but I don't see a reason other plugin managers
wouldn't work. If you run into any issues, please open an issue and I will attempt to resolve it.

### Lazy.nvim
```lua
{
    {
        -- I recommend not installing this a dependency of oil as it isn't required
        -- until you open an oil buffer
        "FerretDetective/oil-git-signs.nvim",
        ft = "oil",
        ---@module "oil_git_signs"
        ---@type oil_git_signs.Config
        opts = {},
    },
    {
        "stevearc/oil.nvim",
        ---@module "oil"
        ---@type oil.SetupOpts
        opts = {
            win_options = {
                signcolumn = "yes:2",
                statuscolumn = "",
            },
        },
        -- Optional dependencies
        dependencies = { { "echasnovski/mini.icons", opts = {} } },
        -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if prefer nvim-web-devicons
    },
}
```

## Options
These are the default options for this plugin. They can be programmatically accessed through
`require("oil-git-signs").defaults`; however, this table **should not** be modified.

```lua
local ogs = require("oil-git-signs")
local GitStatus = ogs.GitStatus

local defaults = {
    -- show a confirm message when performing any git operations
    ---@type boolean|fun(paths: string[]): boolean
    confirm_git_operations = true,
    -- don't show a confirm message for simple git operations
    -- by default a simple git operation is defined as one of the following:
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
```

## Recipes

### Navigation Keymaps
<details>
    <summary>
        Examples of some standard keymaps for jumping to changed files within the oil buffer.
    </summary>

```lua
{

    "FerretDetective/oil-git-signs.nvim",
    ft = "oil",
    opts = {
        keymaps = {
            {
                "n",
                "[H",
                function()
                    if not vim.b.oil_git_signs_exists then
                        return
                    end
                    require("oil-git-signs").jump_to_status("up", -vim.v.count1)
                end,
                { desc = "Jump to first git status" },
            },
            {
                "n",
                "]H",
                function()
                    if not vim.b.oil_git_signs_exists then
                        return
                    end
                    require("oil-git-signs").jump_to_status("down", -vim.v.count1)
                end,
                { desc = "Jump to last git status" },
            },
            {
                "n",
                "[h",
                function()
                    if not vim.b.oil_git_signs_exists then
                        return
                    end
                    require("oil-git-signs").jump_to_status("up", vim.v.count1)
                end,
                { desc = "Jump to prev git status" },
            },
            {
                "n",
                "]h",
                function()
                    if not vim.b.oil_git_signs_exists then
                        return
                    end
                    require("oil-git-signs").jump_to_status("down", vim.v.count1)
                end,
                { desc = "Jump to next git status" },
            },
        },
    },
}
```

</details>

### Lualine Integration
<details>
    <summary>
        Improved integration with lualine to show git information in your statusline when in an oil buffer.
    </summary>

This plugin provides a lualine component for retrieving the index and/or the working_tree status as
a summary similar to lualine's built-in diff component.

The component is called `oil_git_signs_diff` and provides the following additional configuration
options from the standard (non-diff) lualine defaults.

```
oil_git_signs.LualineConfig: {
    diff: {
        index: ("added" | "modified" | "removed")[],
        working_tree: ("added" | "modified" | "removed")[],
    },
}
```

These arrays represent the values that will be taken from index/working tree to generate the
summary. The default configuration includes added, modified, & removed from both the index and
working tree.

To change what git status corresponds to what type in the summary, see `status_classification` in
[Options](#options)

The following is an example configuration which makes use of this component.

```lua
{
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
        extensions = {
            -- Make sure this overrides the default oil.nvim integration
            {
                sections = {
                    lualine_a = {
                        function()
                            local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
                            local adapter_url, path = require("oil.util").parse_url(buf_name)
                            assert(adapter_url ~= nil and path ~= nil, "invalid oil url")

                            local adapter_name = require("oil.config").adapters[adapter_url]

                            return ("%s: %s"):format(adapter_name:upper(), vim.fn.fnamemodify(path, ":~"))
                        end,
                    },
                    lualine_b = {
                        "branch",

                        ---default
                        "oil_git_signs_diff",

                        ---include working tree info only
                        -- { "oil_git_signs_diff", diff = { index = {} } },

                        ---include index info only
                        -- { "oil_git_signs_diff", diff = { working_tree = {} }},

                        ---include only added & modified
                        -- {
                        --     "oil_git_signs_diff",
                        --     diff = {
                        --         index = { "added", "modified" },
                        --         working_tree = { "added", "modified" },
                        --     },
                        -- },
                    },
                    lualine_x = {},
                    lualine_y = { "progress" },
                    lualine_z = { "location" },
                },
                filetypes = { "oil" },
            },

        },
    },
}
```

</details>

### Integration with Oil Git Ignore Recipe
<details>
    <summary>
        Fixes issues that occur when hiding files that are ignored by git.
    </summary>

This fixes issues integrating this plugin when using 
'[Hide gitignored files and show git tracked hidden
files](https://github.com/stevearc/oil.nvim/blob/master/doc/recipes.md#hide-gitignored-files-and-show-git-tracked-hidden-files)'.

```lua
-- helper function to parse output
local function parse_output(proc)
    local result = proc:wait()
    local ret = {}
    if result.code == 0 then
        for line in vim.gsplit(result.stdout, "\n", { plain = true, trimempty = true }) do
            -- Remove trailing slash
            line = line:gsub("/$", "")
            ret[line] = true
        end
    end
    return ret
end

-- build git status cache
local function new_git_status()
    return setmetatable({}, {
        __index = function(self, key)
            local ignore_proc = vim.system(
                { "git", "ls-files", "--ignored", "--exclude-standard", "--others", "--directory" },
                { cwd = key, text = true }
            )
            local tracked_proc = vim.system({ "git", "ls-tree", "HEAD", "--name-only" }, {
                cwd = key,
                text = true,
            })
            local ret = {
                ignored = parse_output(ignore_proc),
                tracked = parse_output(tracked_proc),
            }

            rawset(self, key, ret)
            return ret
        end,
    })
end
local git_status = new_git_status()

-- Clear git status cache on refresh
local refresh = require("oil.actions").refresh
local orig_refresh = refresh.callback
refresh.callback = function(...)
    git_status = new_git_status()
    orig_refresh(...)
end

-- Refresh git signs when toggling hidden
local toggle_hidden = require("oil.actions").toggle_hidden
local orig_toggle_hidden = toggle_hidden.callback
toggle_hidden.callback = function(...)
    orig_toggle_hidden(...)
    require("oil.actions").refresh.callback()
end

require("oil").setup({
    win_options = {
        signcolumn = "yes:2",
        statuscolumn = "",
    },
    view_options = {
        is_hidden_file = function(name, bufnr)
            local dir = require("oil").get_current_dir(bufnr)

            if dir == nil or vim.fn.isdirectory(dir) == 0 then
                return false
            end

            local is_dotfile = vim.startswith(name, ".") and name ~= ".."

            -- if no local directory (e.g. for ssh connections), just hide dotfiles
            if not dir then
                return is_dotfile
            end

            -- dotfiles are considered hidden unless tracked
            if is_dotfile then
                return not git_status[dir].tracked[name]
            end

            -- Check if file is gitignored
            return git_status[dir].ignored[name]
        end,
    },
})

require("oil-git-signs").setup({
    show_ignored = function()
        return require("oil.config").view_options.show_hidden
    end,
})
```

</details>

## API

#### ogs.GitStatus
##### Description
Enum for each of the possible git statuses for `git status --short`.

##### Type
```
ogs.GitStatus: enum {
    SUB_MOD_MODIFIED,
    UNMODIFIED,
    MODIFIED,
    TYPE_CHANGED,
    ADDED,
    DELETED,
    RENAMED,
    COPIED,
    UNMERGED,
    UNTRACKED,
    IGNORED,
}
```

#### ogs.AllStatuses
##### Description
This is an array of all the enum values for each git statuses available.

##### Type
```
ogs.AllStatuses: ogs.GitStatus[]
```

#### ogs.jump_to_status
##### Description
Jump to a numbered count of a given git status on files within oil.

When not specified a default count of 1 is used. Note that you may use negative indices to refer
to the count-th occurrence from the last (e.g. -1 to get the last occurrence, -2 for the second last).

By default, this will jump to any status item however you may specify which ones to jump to for both
the index and the working tree. To do this you pass an array of the statuses you would like to
include to the statuses' table under either the `index` or `working_tree` fields.

##### Type
```
ogs.jump_to_status: function(
    direction: "up"|"down",
    count: integer?,
    statuses: {
        index: ogs.GitStatus[],
        working_tree: ogs.GitStatus[],
    }?
)
```

#### ogs.defaults
##### Description
This is a **readonly** table that contains the default configuration options for this plugin.
See [Options](#options) for more details.

##### Type
```
ogs.Config: {
    show_index: function(entry_name: string, index_status: ogs.GitStatus): boolean,
    show_working_tree: function(entry_name: string, index_status: ogs.GitStatus): boolean,
    show_ignored: function(oil_dir: string): boolean,
    index: table<ogs.GitStatus, { icon: string, hl_group: string }>,
    working_tree: table<ogs.GitStatus, { icon: string, hl_group: string }>,
    status_priority: table<ogs.GitStatus, integer>,
    status_classification: table<ogs.GitStatus, "added"|"removed"|"modified"|nil>,
    keymaps: { [1]: string|string[], [2]: string, [3]: string|function, [4]: vim.keymap.set.Opts? }[]
}
```

#### ogs.options
##### Description
This is the table that contains the current user configuration for this plugin.

##### Type
```
ogs.Config: {
    show_index: function(entry_name: string, index_status: ogs.GitStatus): boolean,
    show_working_tree: function(entry_name: string, index_status: ogs.GitStatus): boolean,
    show_ignored: function(oil_dir: string): boolean,
    index: table<ogs.GitStatus, { icon: string, hl_group: string }>,
    working_tree: table<ogs.GitStatus, { icon: string, hl_group: string }>,
    status_priority: table<ogs.GitStatus, integer>,
    status_classification: table<ogs.GitStatus, "added"|"removed"|"modified"|nil>,
    keymaps: { [1]: string|string[], [2]: string, [3]: string|function, [4]: vim.keymap.set.Opts? }[]
}
```

#### ogs.setup
##### Description
This is the function that sets up this plugin. It must be called for it to work. If no options are
passed the default configuration will be used. See [Options](#options) for more details.

##### Type
```
ogs.setup: function(opts: Config?)
```

#### vim.b.oil_git_signs_exists
##### Description
This is a **readonly** buffer attribute that identifies when oil-git-signs is active in a given oil
buffer.

##### Type
```
vim.b.oil_git_signs_exists: boolean
```

#### vim.b.oil_git_signs_summary
##### Description
This is a **readonly** buffer attribute that contains a table with a summary of the git status for
the current oil buffer. This is useful if for example you want to show the number of git changes in
your status line. See [Lualine Integration](#lualine-integration) for an example.

##### Type
```
vim.b.oil_git_signs_summary: {
    working_tree = { 
        added: integer, 
        removed: integer,
        modified: integer,
    },
    index = { 
        added: integer, 
        removed: integer,
        modified: integer,
    },
}
```

#### vim.b.oil_git_signs_jump_list
##### Description
This is a **readonly** array which maps the one indexed line number of each line in an oil buffer to
the git status of that object. Each line will either give a string of length two where the first
character is the index status and the second character is the working tree status, or `vim.NIL`.

##### Type
```
vim.b.oil_git_signs_jump_list: (string|vim.NIL)[]
```

## Highlights
These are the default highlight and icons configurations which can all be customized. 
See [Options](#options).

| Default Icon    | Default Link  | Index Highlight Group            | Working Tree Highlight Group           |
| --------------- | ------------- | -------------------------------- | -------------------------------------- |
| ` `             | `Normal`      | `OilGitSignsIndexUnmodified`     | `OilGitSignsWorkingTreeUnmodified`     |
| `m`             | `OilChange`   | `OilGitSignsIndexSubModModified` | `OilGitSignsWorkingTreeSubModModified` |
| `M`             | `OilChange`   | `OilGitSignsIndexModified`       | `OilGitSignsWorkingTreeModified`       |
| `T`             | `OilChange`   | `OilGitSignsIndexTypeChanged`    | `OilGitSignsWorkingTreeTypeChanged`    |
| `A`             | `OilCreate`   | `OilGitSignsIndexAdded`          | `OilGitSignsWorkingTreeAdded`          |
| `D`             | `OilDelete`   | `OilGitSignsIndexDeleted`        | `OilGitSignsWorkingTreeDeleted`        |
| `R`             | `OilMove`     | `OilGitSignsIndexRenamed`        | `OilGitSignsWorkingTreeRenamed`        |
| `C`             | `OilCopy`     | `OilGitSignsIndexCopied`         | `OilGitSignsWorkingTreeCopied`         |
| `U`             | `OilChange`   | `OilGitSignsIndexUnmerged`       | `OilGitSignsWorkingTreeUnmerged`       |
| `?`             | `OilCreate`   | `OilGitSignsIndexUntracked`      | `OilGitSignsWorkingTreeUntracked`      |
| `!`             | `NonText`     | `OilGitSignsIndexIgnored`        | `OilGitSignsWorkingTreeIgnored`        |

## Bugs and Issues
If you run into any issues with this plugin please do the following:

##### Ensure you:
1. Are using the latest commit on the main branch of this plugin and oil.nvim.
2. Are using a recent version of Git.
3. Are using a recent version of Neovim.
4. Have checked for any existing/duplicate issues.

##### Create a New Issue:
When creating an issue please include the following:

- oil-git-signs.nvim version/commit (check your package manager)
- oil.nvim version/commit (check your package manager)
- git version (`git --version`)
- neovim version (`nvim --version`)
- a `repro.lua` and any neccessary steps to reproduce the issue (**optional**, see 
[lazy.nvim repro.lua](https://lazy.folke.io/developers#reprolua))

## Contributing
If you have any ideas for features or improvements for this plugin feel free to open an issue or
pull request. I will definitely look at adding it.


