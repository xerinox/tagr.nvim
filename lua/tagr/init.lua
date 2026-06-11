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
  dashboard = {
    layout = "float",             -- "float" or "split"
    split_direction = "vertical", -- "vertical" (right split) or "horizontal" (bottom split)
    split_size = 42,              -- Width/Height size of split window
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
  -- Deep merge options
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Setup binary path in core api runner
  api.setup({ bin_path = M.config.bin_path })
  
  -- Sync configuration options to the dashboard module
  if M.config.dashboard then
    dashboard.config = vim.tbl_deep_extend("force", dashboard.config, M.config.dashboard)
  end

  -- Setup auto-commands to update buffer tags context & draw virtual text
  local group = vim.api.nvim_create_augroup("tagr_events", { clear = true })
  
  -- Fetch buffer information on buffer load/save / navigation
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufEnter" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      local bufnr = ev.buf
      -- Skip empty/special buffers like telescope/quickfix buffers
      if vim.api.nvim_buf_get_option(bufnr, "buftype") == "" then
        statusline.update_cache(bufnr)
      end
    end,
  })

  -- Clear caches if buffer is deleted
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

  -- Custom User interaction trigger to force metadata refresh
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "TagrUpdate",
    callback = function()
      statusline.update_cache(vim.api.nvim_get_current_buf())
    end,
  })

  -- Bind standard native keymaps using vim.keymap.set with proper descriptions
  if M.config.keymaps.enabled then
    vim.keymap.set("n", M.config.keymaps.add_tag, ui.prompt_add_tag, {
      desc = "Tagr: Add tags to current file",
      silent = true,
    })
    vim.keymap.set("n", M.config.keymaps.remove_tag, ui.prompt_remove_tag, {
      desc = "Tagr: Remove tags from current file",
      silent = true,
    })
    vim.keymap.set("n", M.config.keymaps.edit_note, ui.edit_note, {
      desc = "Tagr: Overwrite / Edit whole file metadata notes",
      silent = true,
    })
    vim.keymap.set("n", M.config.keymaps.add_note, ui.add_note_entry, {
      desc = "Tagr: Append new timestamped note entry",
      silent = true,
    })
    vim.keymap.set("n", M.config.keymaps.browse, ui.open_browse_tui, {
      desc = "Tagr: Open interactive browse floating layout",
      silent = true,
    })
    vim.keymap.set("n", M.config.keymaps.dashboard, dashboard.open_inspector, {
      desc = "Tagr: Open metadata / tag dashboard dashboard",
      silent = true,
    })
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

return M
