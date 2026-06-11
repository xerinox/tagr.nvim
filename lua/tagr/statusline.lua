local api = require("tagr.api")
local M = {}
local cache = {}

local function get_glyph(key, default)
  local tagr_main = package.loaded["tagr"]
  if tagr_main and tagr_main.config and tagr_main.config.glyphs then
    return tagr_main.config.glyphs[key] or default
  end
  return default
end

function M.update_cache(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then return end
  
  api.get_file_info(filepath, function(info)
    if type(info) == "table" then
      cache[filepath] = {
        tags = type(info.tags) == "table" and info.tags or {},
        has_note = type(info.note) == "table"
      }
      -- Force statusline rerender after cache updates are complete to avoid displaying stale data.
      vim.cmd("redrawstatus!")
      
      if bufnr == vim.api.nvim_get_current_buf() then
        M.draw_virtual_text(bufnr)
      end
    else
      cache[filepath] = nil
    end
  end)
end

function M.get_statusline_tags()
  local filepath = vim.api.nvim_buf_get_name(0)
  local file_data = cache[filepath]
  if not file_data or #file_data.tags == 0 then
    return ""
  end
  local tag_glyph = get_glyph("tag", "Tags:")
  local prefix = ""
  if file_data.has_note then
    prefix = get_glyph("note", "Note") .. " " .. tag_glyph .. " "
  else
    prefix = tag_glyph .. " "
  end
  return prefix .. "[" .. table.concat(file_data.tags, ", ") .. "]"
end

local ns_id = vim.api.nvim_create_namespace("tagr_virtual_text")
function M.draw_virtual_text(bufnr)
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
      table.insert(pieces, get_glyph("note", "Note"))
    end
    
    if #file_data.tags > 0 then
      table.insert(pieces, get_glyph("tag", "Tags:") .. " " .. table.concat(file_data.tags, "  "))
    end
    
    -- Extmarks allow placing virtual text aligned to the right without modifying buffer text content.
    if #pieces > 0 then
      local virt_text = table.concat(pieces, "  ")
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
        virt_text = { { virt_text, "Comment" } },
        virt_text_pos = "right_align",
      })
    end
  end
end

function M.clear_cache(filepath)
  cache[filepath] = nil
end

return M
