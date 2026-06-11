local api = require("tagr.api")
local statusline = require("tagr.statusline")
local ui = require("tagr.ui")
local dashboard = require("tagr.dashboard")

-- Global completion bridges for vim.ui.input() customlist callbacks
_G.tagr_tag_completion = function(arg_lead, cmd_line, cursor_pos)
  local list = {}
  local raw = vim.fn.system({ "tagr", "list", "tags", "--json" })
  if vim.v.shell_error == 0 then
    local success, parsed = pcall(vim.json.decode, raw)
    if success and type(parsed) == "table" then
      for _, tag in ipairs(parsed) do
        table.insert(list, tag.name)
      end
    end
  end

  -- Return matching list filter
  return vim.tbl_filter(function(item)
    return item:find(arg_lead, 1, true) ~= nil
  end, list)
end

_G.tagr_untag_completion = function(arg_lead, cmd_line, cursor_pos)
  local list = {}
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath ~= "" then
    local raw = vim.fn.system({ "tagr", "file", "show", filepath, "--json" })
    if vim.v.shell_error == 0 then
      local success, parsed = pcall(vim.json.decode, raw)
      if success and parsed.tags then
        list = parsed.tags
      end
    end
  end

  return vim.tbl_filter(function(item)
    return item:find(arg_lead, 1, true) ~= nil
  end, list)
end

local M = {}

M.config = {
  bin_path = "tagr",
  picker = "auto", -- "auto", "telescope", "snacks", or "ui" (fallback)
  virtual_text = {
    enabled = true,
  },
  border = "rounded",
  glyphs = {
    tag = "[Tags]",
    note = "[Note]",
    checked = "[x]",
    unchecked = "[ ]",
    hover = "->",
  },
  dashboard = {
    layout = "float",             -- "float" or "split"
    split_direction = "vertical", -- "vertical" (right split) or "horizontal" (bottom split)
    split_size = 42,              -- Width/Height size of split window
    pinned_tags = {},             -- Pinned tags prioritized at the top of the checkbox checklist
  },
  keymaps = {
    enabled = false, -- Users can set this to true to bind standard shortcuts
    add_tag = "<leader>ta",
    remove_tag = "<leader>tr",
    edit_note = "<leader>te", -- te to Edit the whole Note
    add_note = "<leader>tn",  -- tn to Append a timestamped Note entry
    browse = "<leader>tb",    -- tb to launch Interactive Browser Floating TUI
    dashboard = "<leader>td", -- td to open metadata dashboard panel
  }
}

function M.setup(opts)
  opts = opts or {}
  
  -- Handle a boolean keymaps option gracefully (e.g. keymaps = false) to prevent deep extend
  -- from replacing the configuration table structure with a boolean.
  if type(opts.keymaps) == "boolean" then
    opts.keymaps = { enabled = opts.keymaps }
  end

  -- Deep merge options
  M.config = vim.tbl_deep_extend("force", M.config, opts)
  
  -- Setup binary path in core api runner
  api.setup({ bin_path = M.config.bin_path })
  
  if M.config.dashboard then
    dashboard.config = vim.tbl_deep_extend("force", dashboard.config, M.config.dashboard)
  end

  local group = vim.api.nvim_create_augroup("tagr_events", { clear = true })
  
  -- Query file tags and show visual status overlays whenever entering or writing to a file.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufEnter" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      local bufnr = ev.buf
      -- Skip non-file buffers (like terminal logs, prompt lists, quickfix lists) to avoid superfluous shell queries.
      if vim.bo[bufnr].buftype == "" then
        statusline.update_cache(bufnr)
      end
    end,
  })

  -- Prevent memory leaks by cleaning up the active filepath cache entries when buffers are wiped out.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "*",
    callback = function(ev)
      local filepath = vim.api.nvim_buf_get_name(ev.buf)
      if filepath ~= "" then
        statusline.clear_cache(filepath)
      end
    end,
  })

  -- Allow user processes or custom commands to manually notify tagr that metadata changed.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "TagrUpdate",
    callback = function()
      statusline.update_cache(vim.api.nvim_get_current_buf())
    end,
  })

  -- Register default keyboard mappings with unique descriptions when enabled.
  -- Each keymap is checked to verify it is a valid string, enabling users to selectively 
  -- disable unwanted keys (e.g. setting browse = false).
  local keys = M.config.keymaps
  if keys and keys.enabled then
    local function map(lhs, rhs, desc)
      if type(lhs) == "string" and lhs ~= "" then
        vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
      end
    end

    map(keys.add_tag, ui.prompt_add_tag, "Tagr: Add tags to current file")
    map(keys.remove_tag, ui.prompt_remove_tag, "Tagr: Remove tags from current file")
    map(keys.edit_note, ui.edit_note, "Tagr: Overwrite / Edit whole file metadata notes")
    map(keys.add_note, ui.add_note_entry, "Tagr: Append new timestamped note entry")
    map(keys.browse, ui.open_browse_tui, "Tagr: Open interactive browse floating layout")
    map(keys.dashboard, dashboard.open_inspector, "Tagr: Open metadata / tag dashboard dashboard")
  end
end

-- Export APIs so users can call them or map keybindings dynamically
M.add_tag = ui.prompt_add_tag
M.remove_tag = ui.prompt_remove_tag
M.edit_note = ui.edit_note
M.add_note = ui.add_note_entry
M.browse = ui.open_browse_tui
M.show_tags = statusline.get_statusline_tags
M.open_dashboard = dashboard.open_inspector
M.picker = require("tagr.picker")

return M
