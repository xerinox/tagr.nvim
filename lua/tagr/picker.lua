local api = require("tagr.api")
local M = {}

-- Determine which picker should be used based on configuration and availability
local function get_picker_type()
  local tagr_main = package.loaded["tagr"]
  local config_picker = "auto"
  if tagr_main and tagr_main.config and tagr_main.config.picker then
    config_picker = tagr_main.config.picker
  end

  if config_picker == "snacks" then
    return "snacks"
  elseif config_picker == "telescope" then
    return "telescope"
  elseif config_picker == "ui" then
    return "ui"
  end

  -- Auto-detection sequence
  if pcall(require, "snacks") and Snacks and Snacks.picker then
    return "snacks"
  elseif pcall(require, "telescope") then
    return "telescope"
  else
    return "ui"
  end
end

-- Fallback UI implementation using native vim.ui.select
local ui_picker = {}

function ui_picker.saved_filters_picker()
  api.list_filters(function(filters)
    if type(filters) ~= "table" then filters = {} end

    if #filters == 0 then
      vim.notify("tagr: No saved filters found", vim.log.levels.INFO)
      return
    end

    vim.ui.select(filters, {
      prompt = "Select Saved Filter:",
      format_item = function(item)
        return string.format("%s — %s", item.name, item.description or "No description")
      end
    }, function(choice)
      if choice then
        M.filtered_files_picker(choice.name)
      end
    end)
  end)
end

function ui_picker.filtered_files_picker(filter_name)
  api.search({ "-F", filter_name }, function(files)
    if type(files) ~= "table" then files = {} end

    if #files == 0 then
      vim.notify("tagr: No files matched filter '" .. filter_name .. "'", vim.log.levels.INFO)
      return
    end

    vim.ui.select(files, {
      prompt = "Files matching: " .. filter_name,
      format_item = function(item)
        return string.format("%s [%s]", vim.fs.basename(item.file), table.concat(item.tags, ", "))
      end
    }, function(choice)
      if choice then
        vim.cmd("edit " .. vim.fn.fnameescape(choice.file))
      end
    end)
  end)
end

function ui_picker.tag_search_picker()
  api.list("tags", function(tags_list)
    if type(tags_list) ~= "table" then tags_list = {} end

    if #tags_list == 0 then
      vim.notify("tagr: No tags found in database", vim.log.levels.INFO)
      return
    end

    vim.ui.select(tags_list, {
      prompt = "Select Tag:",
      format_item = function(item)
        return string.format("%s (%d files)", item.name, item.file_count)
      end
    }, function(choice)
      if choice then
        M.files_by_tag_picker(choice.name)
      end
    end)
  end)
end

function ui_picker.files_by_tag_picker(tag_name)
  api.search({ "-t", tag_name }, function(files)
    if type(files) ~= "table" then files = {} end

    if #files == 0 then
      vim.notify("tagr: No files with tag '" .. tag_name .. "'", vim.log.levels.INFO)
      return
    end

    vim.ui.select(files, {
      prompt = "Files with tag: " .. tag_name,
      format_item = function(item)
        return string.format("%s [%s]", vim.fs.basename(item.file), table.concat(item.tags, ", "))
      end
    }, function(choice)
      if choice then
        vim.cmd("edit " .. vim.fn.fnameescape(choice.file))
      end
    end)
  end)
end

-- Snacks.picker implementation
local snacks_picker = {}

-- Resolve the configured note glyph for display in picker rows
local function get_note_glyph()
  local tagr_main = package.loaded["tagr"]
  if tagr_main and tagr_main.config and tagr_main.config.glyphs then
    return tagr_main.config.glyphs.note or "[Note]"
  end
  return "[Note]"
end

-- Build a text preview showing the list of files that have a given tag
local function build_tag_preview(tag_name, file_count)
  local lines = {}
  table.insert(lines, "Tag: #" .. tag_name)
  table.insert(lines, "Files: " .. tostring(file_count))
  table.insert(lines, "")
  table.insert(lines, "Press <CR> to browse files with this tag.")
  return table.concat(lines, "\n")
end

-- Format function for the tag list picker rows
local function format_tag_item(item)
  local ret = {}
  ret[#ret + 1] = { " ", "SnacksPickerLabel" }
  ret[#ret + 1] = { string.format("%-25s ", item.tag_name), "SnacksPickerLabel" }
  ret[#ret + 1] = { string.format("(%d files)", item.file_count), "SnacksPickerComment" }
  return ret
end

-- Format function for the file list picker rows
local function format_file_item(item)
  local ret = {}
  local note_glyph = get_note_glyph()
  -- Fixed-width note column so filenames stay aligned regardless of note presence
  local note_col = item.has_note and (note_glyph .. " ") or string.rep(" ", vim.fn.strdisplaywidth(note_glyph) + 1)
  ret[#ret + 1] = { note_col, "SnacksPickerSpecial" }
  ret[#ret + 1] = { string.format("%-30s ", vim.fs.basename(item.file or "")), "SnacksPickerLabel" }
  ret[#ret + 1] = { table.concat(item.tags or {}, ", "), "SnacksPickerComment" }
  return ret
end

-- Check if a file path looks like a binary file based on extension
local binary_exts = {
  zip = true, tar = true, gz = true, tgz = true, zst = true, pkg = true, xz = true, bz2 = true,
  pdf = true, png = true, jpg = true, jpeg = true, gif = true, webp = true, ico = true, bmp = true,
  mp4 = true, mov = true, avi = true, mkv = true, mp3 = true, flac = true, wav = true,
  exe = true, bin = true, o = true, so = true, dylib = true, dll = true,
  db = true, sqlite = true, sqlite3 = true,
}
local function is_binary_path(path)
  local ext = path:match("%.([^%.]+)$")
  return ext and binary_exts[ext:lower()] or false
end

-- Custom preview for file items: shows file content for text files, a simple message for binary
local function file_preview(ctx)
  if not ctx.item.file then return end
  if is_binary_path(ctx.item.file) then
    ctx.preview:reset()
    ctx.preview:set_lines({ "Binary file: " .. vim.fs.basename(ctx.item.file) })
    return
  end
  local stat = (vim.uv or vim.loop).fs_stat(ctx.item.file)
  if not stat or stat.size == 0 then
    ctx.preview:reset()
    ctx.preview:set_lines({ "Empty file: " .. vim.fs.basename(ctx.item.file) })
    return
  end
  require("snacks.picker.preview").file(ctx)
  -- Reset cursor to top of file so preview starts from line 1
  pcall(vim.api.nvim_win_set_cursor, ctx.win, { 1, 0 })
end

function snacks_picker.saved_filters_picker()
  api.list_filters(function(filters)
    if type(filters) ~= "table" then filters = {} end
    if #filters == 0 then
      vim.notify("tagr: No saved filters found", vim.log.levels.INFO)
      return
    end

    local items = {}
    for _, f in ipairs(filters) do
      table.insert(items, {
        text = f.name .. " " .. (f.description or ""),
        filter_name = f.name,
        preview = {
          text = "Filter: " .. f.name .. "\n" .. (f.description or "No description"),
          ft = "text",
        },
      })
    end

    Snacks.picker({
      title = "Tagr Saved Filters",
      items = items,
      preview = "preview",
      format = "text",
      confirm = function(picker, item)
        picker:close()
        if item and item.filter_name then
          M.filtered_files_picker(item.filter_name)
        end
      end,
    })
  end)
end

function snacks_picker.filtered_files_picker(filter_name)
  api.search({ "-F", filter_name }, function(files)
    if type(files) ~= "table" then files = {} end
    if #files == 0 then
      vim.notify("tagr: No files matched filter '" .. filter_name .. "'", vim.log.levels.INFO)
      return
    end

    local items = {}
    for _, f in ipairs(files) do
      local abs_path = vim.fn.fnamemodify(f.file, ":p")
      local has_note = type(f.note) == "table"
      table.insert(items, {
        text = vim.fs.basename(f.file) .. " " .. table.concat(f.tags or {}, " "),
        file = abs_path,
        tags = f.tags or {},
        has_note = has_note,
      })
    end

    Snacks.picker({
      title = "Files matching: " .. filter_name,
      items = items,
      format = format_file_item,
      preview = file_preview,
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        end
      end,
    })
  end)
end

function snacks_picker.tag_search_picker()
  -- We need both tags list AND the files-per-tag to build the preview.
  -- First fetch all tags, then for each tag fetch files to build preview text.
  api.list("tags", function(tags_list)
    if type(tags_list) ~= "table" then tags_list = {} end
    if #tags_list == 0 then
      vim.notify("tagr: No tags found in database", vim.log.levels.INFO)
      return
    end

    -- For each tag, build a preview listing the files that contain that tag
    local items = {}
    local pending = #tags_list
    for _, t in ipairs(tags_list) do
      api.search({ "-t", t.name }, function(files)
        if type(files) ~= "table" then files = {} end
        local file_lines = {}
        for _, f in ipairs(files) do
          table.insert(file_lines, "  " .. f.file)
        end

        local preview_text = "Tag: #" .. t.name .. "\n"
          .. "Files: " .. tostring(t.file_count) .. "\n"
          .. "\n"
          .. table.concat(file_lines, "\n")

        table.insert(items, {
          text = t.name .. " " .. tostring(t.file_count),
          tag_name = t.name,
          file_count = t.file_count,
          preview = { text = preview_text, ft = "text" },
        })

        pending = pending - 1
        if pending == 0 then
          -- All async tag file lookups complete, now open the picker
          table.sort(items, function(a, b) return a.tag_name < b.tag_name end)

          Snacks.picker({
            title = "Select Tag",
            items = items,
            preview = "preview",
            format = format_tag_item,
            confirm = function(picker, item)
              picker:close()
              if item and item.tag_name then
                M.files_by_tag_picker(item.tag_name)
              end
            end,
          })
        end
      end)
    end
  end)
end

function snacks_picker.files_by_tag_picker(tag_name)
  api.search({ "-t", tag_name }, function(files)
    if type(files) ~= "table" then files = {} end
    if #files == 0 then
      vim.notify("tagr: No files with tag '" .. tag_name .. "'", vim.log.levels.INFO)
      return
    end

    local items = {}
    for _, f in ipairs(files) do
      local abs_path = vim.fn.fnamemodify(f.file, ":p")
      local has_note = type(f.note) == "table"
      table.insert(items, {
        text = vim.fs.basename(f.file) .. " " .. table.concat(f.tags or {}, " "),
        file = abs_path,
        tags = f.tags or {},
        has_note = has_note,
      })
    end

    Snacks.picker({
      title = "Files matching: #" .. tag_name,
      items = items,
      format = format_file_item,
      preview = file_preview,
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        end
      end,
    })
  end)
end

-- Telescope delegate wrapper
local telescope_picker = {}

function telescope_picker.saved_filters_picker()
  require("tagr.telescope").saved_filters_picker()
end

function telescope_picker.filtered_files_picker(filter)
  require("tagr.telescope").filtered_files_picker(filter)
end

function telescope_picker.tag_search_picker()
  require("tagr.telescope").tag_search_picker()
end

function telescope_picker.files_by_tag_picker(tag)
  require("tagr.telescope").files_by_tag_picker(tag)
end

-- Exported unified functions mapping dynamically to standard backend implementations
function M.saved_filters_picker()
  local pt = get_picker_type()
  if pt == "snacks" then
    snacks_picker.saved_filters_picker()
  elseif pt == "telescope" then
    telescope_picker.saved_filters_picker()
  else
    ui_picker.saved_filters_picker()
  end
end

function M.filtered_files_picker(filter_name)
  local pt = get_picker_type()
  if pt == "snacks" then
    snacks_picker.filtered_files_picker(filter_name)
  elseif pt == "telescope" then
    telescope_picker.filtered_files_picker(filter_name)
  else
    ui_picker.filtered_files_picker(filter_name)
  end
end

function M.tag_search_picker()
  local pt = get_picker_type()
  if pt == "snacks" then
    snacks_picker.tag_search_picker()
  elseif pt == "telescope" then
    telescope_picker.tag_search_picker()
  else
    ui_picker.tag_search_picker()
  end
end

function M.files_by_tag_picker(tag_name)
  local pt = get_picker_type()
  if pt == "snacks" then
    snacks_picker.files_by_tag_picker(tag_name)
  elseif pt == "telescope" then
    telescope_picker.files_by_tag_picker(tag_name)
  else
    ui_picker.files_by_tag_picker(tag_name)
  end
end

return M