-- Define Neovim User Commands mapping key actions

vim.api.nvim_create_user_command("TagrAddTag", function(opts)
  local ui = require("tagr.ui")
  if opts.args ~= "" then
    -- Explicitly trim and parse only a single tag from direct command-line arguments
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return end
    local tag = vim.trim(opts.args)
    if tag ~= "" then
      require("tagr.api").add_tags(filepath, { tag }, function()
        vim.notify("Tagged: " .. tag, vim.log.levels.INFO)
        vim.cmd("silent! doautocmd User TagrUpdate")
      end)
    end
  else
    ui.prompt_add_tag()
  end
end, {
  nargs = "?",
  complete = function(arg_lead)
    local completion_list = {}
    local raw_output = vim.fn.system(require("tagr.api").cmd({"list", "tags", "--json"}))
    if vim.v.shell_error == 0 then
      local success, parsed = pcall(vim.json.decode, raw_output)
      if success then
        for _, tag in ipairs(parsed) do
          table.insert(completion_list, tag.name)
        end
      end
    end
    return vim.tbl_filter(function(item)
      return item:find(arg_lead, 1, true) ~= nil
    end, completion_list)
  end,
})

vim.api.nvim_create_user_command("TagrRemoveTag", function(opts)
  local ui = require("tagr.ui")
  if opts.args ~= "" then
    -- Explicitly trim and parse only a single tag from direct command-line arguments
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return end
    local tag = vim.trim(opts.args)
    if tag ~= "" then
      require("tagr.api").remove_tags(filepath, { tag }, function()
        vim.notify("Removed tag: " .. tag, vim.log.levels.INFO)
        vim.cmd("silent! doautocmd User TagrUpdate")
      end)
    end
  else
    ui.prompt_remove_tag()
  end
end, {
  nargs = "?",
  complete = function(arg_lead)
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return {} end
    -- Only suggest tags belonging to the current file for removal
    local completion_list = {}
    local raw_output = vim.fn.system(require("tagr.api").cmd({"file", "show", filepath, "--json"}))
    if vim.v.shell_error == 0 then
      local success, parsed = pcall(vim.json.decode, raw_output)
      if success and parsed.tags then
        completion_list = parsed.tags
      end
    end
    return vim.tbl_filter(function(item)
      return item:find(arg_lead, 1, true) ~= nil
    end, completion_list)
  end,
})

vim.api.nvim_create_user_command("TagrNoteEdit", function()
  require("tagr.ui").edit_note()
end, {})

vim.api.nvim_create_user_command("TagrNoteAdd", function()
  require("tagr.ui").add_note_entry()
end, {})

vim.api.nvim_create_user_command("TagrBrowse", function()
  require("tagr.ui").open_browse_tui()
end, {})

vim.api.nvim_create_user_command("Tagr", function()
  require("tagr.dashboard").open_inspector()
end, {})

-- Accepts optional tag parameters, e.g. :TagrSearchTags notes
-- With a param, pre-fills the tag picker search field for fuzzy matching instead of exact CLI lookup
vim.api.nvim_create_user_command("TagrSearchTags", function(opts)
  local picker = require("tagr.picker")
  picker.tag_search_picker(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  complete = function(arg_lead)
    -- Provide absolute command-line autocomplete matching available tags
    local completion_list = {}
    local raw_output = vim.fn.system(require("tagr.api").cmd({"list", "tags", "--json"}))
    if vim.v.shell_error == 0 then
      local success, parsed = pcall(vim.json.decode, raw_output)
      if success then
        for _, tag in ipairs(parsed) do
          table.insert(completion_list, tag.name)
        end
      end
    end
    return vim.tbl_filter(function(item)
      return item:find(arg_lead, 1, true) ~= nil
    end, completion_list)
  end,
})

-- Accepts optional filter name, e.g. :TagrFilters rust-only
vim.api.nvim_create_user_command("TagrFilters", function(opts)
  local picker = require("tagr.picker")
  if opts.args ~= "" then
    picker.filtered_files_picker(opts.args)
  else
    picker.saved_filters_picker()
  end
end, {
  nargs = "?",
  complete = function(arg_lead)
    -- Provide prompt autocomplete matching saved filters list
    local completion_list = {}
    local raw_output = vim.fn.system(require("tagr.api").cmd({"filter", "list", "--json"}))
    if vim.v.shell_error == 0 then
      local success, parsed = pcall(vim.json.decode, raw_output)
      if success then
        for _, filter in ipairs(parsed) do
          table.insert(completion_list, filter.name)
        end
      end
    end
    return vim.tbl_filter(function(item)
      return item:find(arg_lead, 1, true) ~= nil
    end, completion_list)
  end,
})
