local api = require("tagr.api")
local M = {}
local cache = {} -- filepath -> {tags = {}, has_note = bool}

-- Update cache values for specified buffer
function M.update_cache(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then return end
  
  -- Query file status asynchronously
  api.get_file_info(filepath, function(info)
    if type(info) == "table" then
      cache[filepath] = {
        tags = type(info.tags) == "table" and info.tags or {},
        has_note = type(info.note) == "table"
      }
      -- Trigger redraw across all panels and statuslines
      vim.cmd("redrawstatus!")
      
      -- If current buffer, refresh virtual text as well
      if bufnr == vim.api.nvim_get_current_buf() then
        M.draw_virtual_text(bufnr)
      end
    else
      cache[filepath] = nil
    end
  end)
end

-- Get tags for current active buffer as a structured string for statusline integrations
function M.get_statusline_tags()
  local filepath = vim.api.nvim_buf_get_name(0)
  local file_data = cache[filepath]
  if not file_data or #file_data.tags == 0 then
    return ""
  end
  local prefix = file_data.has_note and "📝 🏷️ " or "🏷️ "
  return prefix .. "[" .. table.concat(file_data.tags, ", ") .. "]"
end

-- Set top-line virtual text overlay showing tags inside buffer margin
local ns_id = vim.api.nvim_create_namespace("tagr_virtual_text")
function M.draw_virtual_text(bufnr)
  -- Respect configuration setup toggling virtual text
  local tagr_main = package.loaded["tagr"]
  if tagr_main and tagr_main.config and not tagr_main.config.virtual_text.enabled then
    return
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local file_data = cache[filepath]
  
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  if file_data then
    local pieces = {}
    
    if file_data.has_note then
      table.insert(pieces, "📝")
    end
    
    if #file_data.tags > 0 then
      table.insert(pieces, "🏷️  " .. table.concat(file_data.tags, "  "))
    end
    
    -- Only draw extmarks/virtual text if we actually have notes OR tags (or both)
    if #pieces > 0 then
      local virt_text = table.concat(pieces, "  ")
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
        virt_text = { { virt_text, "Comment" } },
        virt_text_pos = "right_align",
      })
    end
  end
end

-- Clear cache on exit/buffer wipeouts to avoid memory leaks
function M.clear_cache(filepath)
  cache[filepath] = nil
end

return M
