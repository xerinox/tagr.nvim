# tagr.nvim

`tagr.nvim` is a Neovim plugin for **tagr**—the filesystem tagging and metadata organization CLI. It provides interactive prompts, metadata dashboards, fuzzy-finding pickers, and asynchronous workflows, allowing you to organize, search, and navigate tagged files.

---

## Features

- **Asynchronous Execution**: Interacts with the `tagr` Go binary using non-blocking Neovim systems, preventing UI freezes.
- **Dashboard Inspector**: Hover-based floating or split panel to view file metadata, toggle tags via checkboxes, see notes history, and edit metadata.
- **Fuzzy Finder Integration**: Native support for **Telescope** and **Snacks.picker** as picker backends, alongside a built-in `vim.ui.select` fallback.
- **Markdown Notes Editor**: Access dedicated visual editor buffers to append or overwrite file notes with timestamped logs.
- **Tag Autocompletion**: Tab completion matches global and buffer-local tag indices seamlessly.
- **Virtual Text Overlays**: Render current file tags and note indicators right-aligned on the first line of active buffers.
- **Statusline API**: Helper methods designed to return formatted strings for easy integration with standard statusline plugins (like `lualine`).

---

## Prerequisites

The **`tagr`** command-line interface must be installed and available in your system environment PATH.

```bash
# Verify tagr binary is accessible
tagr --version
```

---

## Installation

Install using your preferred Neovim package manager.

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "xerinox/tagr.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim", -- Optional: for file pickers/search
  },
  config = function()
    require("tagr").setup({
      keymaps = {
        enabled = true,
      }
    })
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'xerinox/tagr.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim' -- Optional
  },
  config = function()
    require('tagr').setup({
      keymaps = {
        enabled = true,
      }
    })
  end
}
```

---

## Configuration

Pass configuration options to the `setup` function to customize layouts, behavior, and keymaps:

```lua
require("tagr").setup({
  -- Command executable or absolute path
  bin_path = "tagr",

  -- Selected picker backend: "auto" (autodetects Snacks -> Telescope -> vim.ui.select), "telescope", "snacks", or "ui"
  picker = "auto",

  -- Configure buffer overlay metadata
  virtual_text = {
    enabled = true,
  },

  -- Floating window border styling
  border = "rounded",

  -- Deep inspector dashboard settings
  dashboard = {
    layout = "float",             -- "float" or "split"
    split_direction = "vertical", -- "vertical" or "horizontal"
    split_size = 42,              -- split panel width/height
  },

  -- Keybindings management
  keymaps = {
    enabled = false, -- Set to true to enable standard keymaps
    add_tag = "<leader>ta",     -- Add tags to current file
    remove_tag = "<leader>tr",  -- Remove tags from current file
    edit_note = "<leader>te",   -- Edit/Overwrite the entire notes file
    add_note = "<leader>tn",    -- Append a timestamped notes entry
    browse = "<leader>tb",      -- Launch floating terminal file browser
    dashboard = "<leader>td",   -- Open metadata dashboard panel
  }
})
```

---

## Commands & Keymaps

### User Commands

| Command | Native Method | Description |
| :--- | :--- | :--- |
| `:Tagr` | Dashboard | Open the metadata and tag management dashboard |
| `:TagrAddTag [tag]` | `add_tag` | Add tag (prompts with autocompletion if no argument is passed) |
| `:TagrRemoveTag [tag]` | `remove_tag` | Remove tag (prompts with local buffer tags autocomplete if empty) |
| `:TagrNoteEdit` | `edit_note` | Edit markdown notes in a floating editor buffer |
| `:TagrNoteAdd` | `add_note` | Append a new markdown entry to notes (adds timestamp automatically) |
| `:TagrBrowse` | `browse` | Open the interactive `tagr browse` TUI in a floating terminal window |
| `:TagrSearchTags [tag]` | Telescope picker | Choose from globally defined tags and list their target files |
| `:TagrFilters [name]` | Telescope picker | Choose from saved tagr filters and view matched files |

To define keymaps manually when `keymaps.enabled = false`:

```lua
vim.keymap.set("n", "<leader>ta", require("tagr").add_tag, { desc = "Tagr: Add tag" })
vim.keymap.set("n", "<leader>tr", require("tagr").remove_tag, { desc = "Tagr: Remove tag" })
vim.keymap.set("n", "<leader>td", require("tagr.dashboard").open_inspector, { desc = "Tagr: Dashboard" })
```

---

## Dashboard Navigation

Within the inspector panel opened via `:Tagr` or custom keymaps, navigate with these keys:

- `j` / `k` : Hover down / up through tags.
- `g` / `G` : Jump to first / last tag.
- `<CR>` : Toggle selected tag connection on current buffer.
- `t` : Add a new custom tag to the global list and buffer.
- `e` : Transition into markdown notes editor buffer.
- `q` / `<ESC>` : Close the dashboard inspector panel.

---

## Pickers and Search

Integrate with your pickers manually using the unified picker API. This automatically respects your configured picker backend (`snacks`, `telescope`, or built-in `vim.ui.select`):

```lua
-- List saved filters to view match groups
require("tagr.picker").saved_filters_picker()

-- Search through all tags interactively
require("tagr.picker").tag_search_picker()

-- Search files containing a specific tag directly
require("tagr.picker").files_by_tag_picker("important")
```

If you prefer to invoke Telescope-specific modules directly, you can still call:

```lua
require("tagr.telescope").tag_search_picker()
```

---

## Statusline Integration

Integrate the active buffer's tags list with your statusline plugins (such as `lualine.nvim`):

```lua
-- Example: lualine.nvim setup configuration
require('lualine').setup({
  sections = {
    lualine_x = {
      {
        function()
          return require("tagr.statusline").get_statusline_tags()
        end,
        color = { fg = "#ff9e64" }
      }
    }
  }
})
```

---

## License

MIT
