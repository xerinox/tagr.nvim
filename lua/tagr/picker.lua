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
        text = string.format("%-20s │ %s", f.name, f.description or "No description"),
        value = f.name,
        name = f.name,
      })
    end

    Snacks.picker({
      title = "Tagr Saved Filters",
      items = items,
      actions = {
        confirm = function(picker, item)
          picker:close()
          if item then
            M.filtered_files_picker(item.value)
          end
        end,
      },
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
      table.insert(items, {
        text = string.format("%s [%s]", vim.fs.basename(f.file), table.concat(f.tags, ", ")),
        file = f.file,
      })
    end

    Snacks.picker({
      title = "Files matching: " .. filter_name,
      items = items,
      actions = {
        confirm = function(picker, item)
          picker:close()
          -- In Snacks.picker, the selected item is wrapped inside a structure. 
          -- We must read from item.file (since we populated it inside items), or fallback 
          -- to reading from item[1] or item.text depending on the state of the object.
          if item and item.file then
            vim.cmd("edit " .. vim.fn.fnameescape(item.file))
          end
        end,
      },
    })
  end)
end

function snacks_picker.tag_search_picker()
  api.list("tags", function(tags_list)
    if type(tags_list) ~= "table" then tags_list = {} end

    if #tags_list == 0 then
      vim.notify("tagr: No tags found in database", vim.log.levels.INFO)
      return
    end

    local items = {}
    for _, t in ipairs(tags_list) do
      table.insert(items, {
        text = string.format("%-25s (%d files)", t.name, t.file_count),
        value = t.name,
      })
    end

    Snacks.picker({
      title = "Select Tag",
      items = items,
      actions = {
        confirm = function(picker, item)
          picker:close()
          -- Extract the target tag name from the item's custom value table structure.
          if item and item.value then
            M.files_by_tag_picker(item.value)
          end
        end,
      },
    })
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
      table.insert(items, {
        text = string.format("%s \t[%s]", vim.fs.basename(f.file), table.concat(f.tags, ", ")),
        file = f.file,
      })
    end

    Snacks.picker({
      title = "Files matching: #" .. tag_name,
      items = items,
      actions = {
        confirm = function(picker, item)
          picker:close()
          if item and item.file then
            vim.cmd("edit " .. vim.fn.fnameescape(item.file))
          end
        end,
      },
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