local api = require("tagr.api")
local M = {}

-- Helper to check if a buffer is taggable (not empty, no special directory lists/filetypes)
local function is_taggable_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  
  if filepath == "" then
    return false, "Cannot tag files with empty names"
  end

  -- Block directory file lists (netrw, dirvish, oil, etc.)
  if vim.fn.isdirectory(filepath) == 1 then
    return false, "Cannot tag directory structures"
  end

  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local blocked_filetypes = {
    netrw = true,
    oil = true,
    dirvish = true,
    NvimTree = true,
    neo_tree = true,
    TelescopePrompt = true,
    qf = true, -- Quickfix
  }
  if blocked_filetypes[filetype] then
    return false, "Cannot tag special buffer type: " .. filetype
  end

  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  if buftype ~= "" then
    return false, "Cannot tag non-file buffers"
  end

  return true, nil
end

-- Open a custom floating buffer to edit the full file notes (overwrites the note)
function M.edit_note(filepath)
  local is_taggable, err = is_taggable_buffer()
  if not is_taggable then
    vim.notify("tagr.nvim: " .. err, vim.log.levels.WARN)
    return
  end

  filepath = filepath or vim.api.nvim_buf_get_name(0)
  
  api.get_file_info(filepath, function(info)
    -- Handle missing record or non-table values gracefully
    local note_content = ""
    if type(info) == "table" and type(info.note) == "table" and type(info.note.content) == "string" then
      note_content = info.note.content
    end
    
    -- Create a standard, loaded file buffer so it is saveable like a normal file
    local buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_option(buf, "buftype", "acwrite") -- Intercept write callbacks (:w)
    vim.api.nvim_buf_set_name(buf, "tagr://note-edit/" .. vim.fs.basename(filepath))
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(note_content, "\n"))

    -- Layout configurations (60% width, 50% height, centered)
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

    -- Auto-save note to tagr database when saving buffer via :w
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local content = table.concat(lines, "\n")
        
        -- Run "tagr note add <FILE> <CONTENT>" equivalent command to modify whole file
        -- On tagr side, replacing note content is done via "tagr note add" with the whole file
        -- which replaces.
        api.run_tagr({ "note", "add", filepath, content }, function()
          vim.schedule(function()
            -- Mark the buffer as saved / unchanged
            vim.api.nvim_buf_set_option(buf, "modified", false)
            vim.notify("Note overwritten in tagr database!", vim.log.levels.INFO)
            -- Trigger layout refresh
            vim.cmd("silent! doautocmd User TagrUpdate")
          end)
        end)
      end,
    })
  end)
end

-- Open a custom floating buffer to append a timestamped entry (NoteAdd)
function M.add_note_entry(filepath)
  local is_taggable, err = is_taggable_buffer()
  if not is_taggable then
    vim.notify("tagr.nvim: " .. err, vim.log.levels.WARN)
    return
  end

  filepath = filepath or vim.api.nvim_buf_get_name(0)

  -- Create a standard writable buffer
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_option(buf, "buftype", "acwrite") -- Intercept write callbacks (:w)
  vim.api.nvim_buf_set_name(buf, "tagr://note-add/" .. vim.fs.basename(filepath))
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  
  -- Put helper comment lines into the new buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "<!-- New entry to append to file notes -->",
    "<!-- Will generate standard timestamp heading automatically -->",
    "",
  })
  
  -- Set cursor to line 3 (end of buffer) for easy writing
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    once = true,
    callback = function()
      vim.api.nvim_win_set_cursor(0, {3, 0})
    end,
  })

  -- Layout configurations (60% width, 40% height, centered)
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
          vim.api.nvim_buf_set_option(buf, "modified", false)
          vim.notify("Note entry appended successfully with timestamp heading!", vim.log.levels.INFO)
          -- Close the window automatically after appending
          pcall(vim.api.nvim_win_close, win, true)
          -- Trigger layout refresh
          vim.cmd("silent! doautocmd User TagrUpdate")
        end)
      end)
    end,
  })
end

-- Interactive Tagging Input with Autocomplete
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
      
      -- Support split by comma and/or spacing boundaries cleanly
      local raw_tags = vim.split(input, ",")
      local tags_to_add = {}
      for _, t in ipairs(raw_tags) do
        -- Trim any leading or trailing spaces from each individual tag
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

-- Interactive Untagging Input with Autocomplete
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
        -- Trim any leading or trailing spaces from each individual tag to delete
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

-- Open fully-interactive TUI browse mode centered inside a floating terminal buffer
function M.open_browse_tui()
  -- Create floating buffer target
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

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

  -- Build final command utilizing the user-configured tagr binary path
  local bin_path = api.bin_path or "tagr"
  
  -- Open terminal mode running the TUI browse command with selection target redirection
  local temp_output_file = vim.fn.tempname()
  local cmd = string.format("%s browse -q --selected-output %s", vim.fn.shellescape(bin_path), vim.fn.shellescape(temp_output_file))
  
  -- Start Neovim termopen stream
  vim.fn.termopen(cmd, {
    on_exit = function()
      vim.schedule(function()
        -- Safely force wipe window and buffer
        pcall(vim.api.nvim_win_close, win, true)
        
        -- Check and load any selections captured on disk on exit
        if vim.fn.filereadable(temp_output_file) == 1 then
          local lines = vim.fn.readfile(temp_output_file)
          -- Remove temporary output file safely
          vim.fn.delete(temp_output_file)
          
          for _, file in ipairs(lines) do
            local trimmed = vim.trim(file)
            if trimmed ~= "" then
              vim.cmd("edit " .. vim.fn.fnameescape(trimmed))
            end
          end
        end
        -- Trigger global tag state update
        vim.cmd("silent! doautocmd User TagrUpdate")
      end)
    end,
  })

  -- Enter terminal insert mode immediately
  vim.cmd("startinsert")
end

return M
