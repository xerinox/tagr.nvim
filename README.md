# tagr.nvim

`tagr.nvim` is a Neovim plugin for **tagr**—the filesystem tagging and metadata organization CLI. It provides interactive prompts, metadata dashboards, fuzzy-finding pickers, and asynchronous workflows, allowing you to organize, search, and navigate tagged files.

---

## Features

- **Asynchronous Execution**: Interacts with the `tagr` Go binary using non-blocking Neovim systems, preventing UI freezes.
- **Dashboard Inspector**: Hover-based floating or split panel to view file metadata, toggle tags via checkboxes, see notes history, and edit metadata.
- **Fuzzy Finder Integration**: Native support for **Snacks.picker** and **Telescope** as picker backends, with styled format columns, file previews, and binary-file handling. Falls back to built-in `vim.ui.select` when neither is installed.
- **Fuzzy Tag Search**: Tag searches use the picker's built-in fuzzy matcher — typing a partial tag name narrows the list live. Exact matches from command-line autocomplete skip the tag picker and jump straight to matching files.
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

Install using your preferred Neovim package manager. Note that pickers (Telescope or Snacks) are strictly optional; if none are installed, the plugin will seamlessly fall back to using native Neovim select menus (`vim.ui.select`).

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "xerinox/tagr.nvim",
  dependencies = {
    -- Optional: Only if you want fuzzy-search pickers
    "nvim-telescope/telescope.nvim", 
    -- Alternatively, "folke/snacks.nvim" is fully supported out of the box
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

### Using Neovim packages (`vim.pack.add` / `mini.deps`)

If you use Neovim's built-in package system or a modern loader like `mini.deps` with `vim.pack.add`:

```lua
-- Add the plugin to your package manager loadout.
-- This ensures the plugin is immediately added to the runtimepath on boot (e.g. for `nvim .` netrw/oil directories).
vim.pack.add({
  { src = "https://github.com/xerinox/tagr.nvim" },
})

-- Initialize and bind parameters immediately so commands like `:Tagr` are defined before reading directories
local ok, tagr = pcall(require, 'tagr')
if ok then
  tagr.setup({
    keymaps = {
      enabled = true,
    }
  })
end
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'xerinox/tagr.nvim',
  requires = {
    'nvim-telescope/telescope.nvim' -- Optional: for fuzzy search layouts
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

  -- Fully customizable status indicators and visual UI labels (defaults to emoji-free ASCII)
  glyphs = {
    tag = "[Tags]",
    note = "[Note]",
    checked = "[x]",
    unchecked = "[ ]",
    hover = "->",
  },

  -- Deep inspector dashboard settings
  dashboard = {
    layout = "float",             -- "float" or "split"
    split_direction = "vertical", -- "vertical" or "horizontal"
    split_size = 42,              -- split panel width/height
    pinned_tags = { "todo", "important" }, -- Tags prioritized at the top of the checklist
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
| `:TagrSearchTags [tag]` | Fuzzy picker | Fuzzy-search tags; exact match skips to files, partial opens the tag picker pre-filled |
| `:TagrFilters [name]` | Fuzzy picker | Choose from saved tagr filters and view matched files |

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

The picker system provides a two-step workflow for tag-based file navigation:

1. **Tag picker** — Lists all tags with file counts. The preview pane shows which files belong to each tag. Fuzzy filtering narrows the list as you type.
2. **File picker** — After selecting a tag, a second picker shows matching files with syntax-highlighted previews. Files with notes display a note indicator in the list.

Binary and empty files are handled gracefully in preview (no debug table dumps).

Use the unified picker API directly if needed:

```lua
-- Open the fuzzy tag picker (optional pattern pre-fills the search field)
require("tagr.picker").tag_search_picker("rust")

-- Skip straight to files for a known tag
require("tagr.picker").files_by_tag_picker("important")

-- Browse saved filters
require("tagr.picker").saved_filters_picker()
```

All pickers support `<C-q>` to send results to the quickfix list.

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
