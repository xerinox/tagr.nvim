local api = require("tagr.api")
local M = {}

-- Checks if a buffer can logically be tagged. Special files, system directories, internal trees,
-- and non-file quickfix windows must be excluded to prevent polluting the tag database with metadata.
local function is_taggable_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  
  if filepath == "" then
    return false, "Cannot tag files with empty names"
  end

  if vim.fn.isdirectory(filepath) == 1 then
    return false, "Cannot tag directory structures"
  end

  local filetype = vim.bo[bufnr].filetype
  local blocked_filetypes = {
    netrw = true,
    oil = true,
    dirvish = true,
    NvimTree = true,
    neo_tree = true,
    TelescopePrompt = true,
    qf = true,
  }
  if blocked_filetypes[filetype] then
    return false, "Cannot tag special buffer type: " .. filetype
  end

  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return false, "Cannot tag non-file buffers"
  end

  return true, nil
end

function M.edit_note(filepath)
  local is_taggable, err = is_taggable_buffer()
  if not is_taggable then
    vim.notify("tagr.nvim: " .. err, vim.log.levels.WARN)
    return
  end

  filepath = filepath or vim.api.nvim_buf_get_name(0)
  
  api.get_file_info(filepath, function(info)
    local note_content = ""
    if type(info) == "table" and type(info.note) == "table" and type(info.note.content) == "string" then
      note_content = info.note.content
    end
    
    local buf = vim.api.nvim_create_buf(false, false)
    -- "acwrite" tells Neovim we will manually handle writing operations, so when the user calls :w,
    -- it won't try to write a file at the visual "tagr://" URI.
    vim.bo[buf].buftype = "acwrite"
    vim.api.nvim_buf_set_name(buf, "tagr://note-edit/" .. vim.fs.basename(filepath))
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(note_content, "\n"))

    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.5)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
      title = " Edit Note: " .. vim.fs.basename(filepath) .. " ",
      title_pos = "center",
    })

    -- We utilize a custom write callback instead of physical writes, converting buffer state
    -- back into database additions asynchronously.
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local content = table.concat(lines, "\n")
        
        api.run_tagr({ "note", "add", filepath, content }, function()
          vim.schedule(function()
            -- Stop Neovim from complaining about unsaved modifications when wiping the buffer.
            vim.bo[buf].modified = false
            vim.notify("Note overwritten in tagr database!", vim.log.levels.INFO)
            vim.cmd("silent! doautocmd User TagrUpdate")
          end)
        end)
      end,
    })
  end)
end

function M.add_note_entry(filepath)
  local is_taggable, err = is_taggable_buffer()
  if not is_taggable then
    vim.notify("tagr.nvim: " .. err, vim.log.levels.WARN)
    return
  end

  filepath = filepath or vim.api.nvim_buf_get_name(0)

  local buf = vim.api.nvim_create_buf(false, false)
  vim.bo[buf].buftype = "acwrite"
  vim.api.nvim_buf_set_name(buf, "tagr://note-add/" .. vim.fs.basename(filepath))
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  
  -- Inject markdown hint guidelines for a neat logging workflow
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "<!-- New entry to append to file notes -->",
    "<!-- Will generate standard timestamp heading automatically -->",
    "",
  })
  
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    once = true,
    callback = function()
      -- Place the typing cursor directly below html comments to save users a keystroke.
      vim.api.nvim_win_set_cursor(0, {3, 0})
    end,
  })

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Append Note Entry: " .. vim.fs.basename(filepath) .. " ",
    title_pos = "center",
  })

  -- Append note entry on write (:w)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- Strip comments on save
      local clean_lines = {}
      for _, line in ipairs(lines) do
        if not line:match("^%s*<!%-%-") then
          table.insert(clean_lines, line)
        end
      end
      
      local content = vim.trim(table.concat(clean_lines, "\n"))
      if content == "" then
        vim.notify("tagr.nvim: Cannot append empty entries", vim.log.levels.WARN)
        return
      end

      -- The tagr binary CLI "tagr note add <FILE> <ENTRY>" appends with formatting and headers automatically
      api.run_tagr({ "note", "add", filepath, content }, function()
        vim.schedule(function()
          vim.bo[buf].modified = false
          vim.notify("Note entry appended successfully with timestamp heading!", vim.log.levels.INFO)
          pcall(vim.api.nvim_win_close, win, true)
          vim.cmd("silent! doautocmd User TagrUpdate")
        end)
      end)
    end,
  })
end

function M.prompt_add_tag()
  local is_taggable, err = is_taggable_buffer()
  if not is_taggable then
    vim.notify("tagr.nvim: " .. err, vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)

  api.list("tags", function(tags)
    local completion_list = {}
    if type(tags) == "table" then
      for _, tag in ipairs(tags) do
        table.insert(completion_list, tag.name)
      end
    end

    vim.ui.input({
      prompt = "Add tags (comma-separated): ",
      completion = "customlist,v:lua.tagr_tag_completion",
    }, function(input)
      if not input or input == "" then return end
      
      local raw_tags = vim.split(input, ",")
      local tags_to_add = {}
      for _, t in ipairs(raw_tags) do
        -- Trim space padding to prevent malformed tags in database.
        local trimmed = vim.trim(t)
        if trimmed ~= "" then
          table.insert(tags_to_add, trimmed)
        end
      end

      if #tags_to_add > 0 then
        api.add_tags(filepath, tags_to_add, function()
          vim.notify("Tagged: " .. table.concat(tags_to_add, ", "), vim.log.levels.INFO)
          vim.cmd("silent! doautocmd User TagrUpdate")
        end)
      end
    end)
  end)
end

function M.prompt_remove_tag()
  local is_taggable, err = is_taggable_buffer()
  if not is_taggable then
    vim.notify("tagr.nvim: " .. err, vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)

  api.get_file_info(filepath, function(info)
    local existing_tags = info and info.tags or {}
    if #existing_tags == 0 then
      vim.notify("File has no tags to remove", vim.log.levels.INFO)
      return
    end

    vim.ui.input({
      prompt = "Remove tags (" .. table.concat(existing_tags, ", ") .. "): ",
      completion = "customlist,v:lua.tagr_untag_completion",
    }, function(input)
      if not input or input == "" then return end
      local tags_to_remove = vim.split(input, ",")
      local clean_tags = {}
      for _, t in ipairs(tags_to_remove) do
        local trimmed = vim.trim(t)
        if trimmed ~= "" then
          table.insert(clean_tags, trimmed)
        end
      end

      if #clean_tags > 0 then
        api.remove_tags(filepath, clean_tags, function()
          vim.notify("Removed tags: " .. table.concat(clean_tags, ", "), vim.log.levels.INFO)
          vim.cmd("silent! doautocmd User TagrUpdate")
        end)
      end
    end)
  end)
end

function M.open_browse_tui()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Tagr Interactive Browser ",
    title_pos = "center",
  })

  local bin_path = api.bin_path or "tagr"
  
  -- Generates a temporary filename to pass to the TUI; the TUI writes selected paths to it on exit,
  -- allowing Neovim to catch the files selected by the user.
  local temp_output_file = vim.fn.tempname()
  local cmd
  if api.db then
    cmd = string.format("%s browse -q --selected-output %s --db %s", vim.fn.shellescape(bin_path), vim.fn.shellescape(temp_output_file), vim.fn.shellescape(api.db))
  else
    cmd = string.format("%s browse -q --selected-output %s", vim.fn.shellescape(bin_path), vim.fn.shellescape(temp_output_file))
  end
  
  vim.fn.termopen(cmd, {
    on_exit = function()
      vim.schedule(function()
        pcall(vim.api.nvim_win_close, win, true)
        
        if vim.fn.filereadable(temp_output_file) == 1 then
          local lines = vim.fn.readfile(temp_output_file)
          vim.fn.delete(temp_output_file)
          
          for _, file in ipairs(lines) do
            local trimmed = vim.trim(file)
            if trimmed ~= "" then
              vim.cmd("edit " .. vim.fn.fnameescape(trimmed))
            end
          end
        end
        vim.cmd("silent! doautocmd User TagrUpdate")
      end)
    end,
  })

  vim.cmd("startinsert")
end

return M
