local api = require("tagr.api")
local M = {}

-- Safely verify Telescope is fully loaded to prevent hard crashes for users who do not use Telescope as their active picker.
local has_telescope, pickers = pcall(require, "telescope.pickers")
if not has_telescope then
  return {
    saved_filters_picker = function()
      vim.notify("Telescope is not installed or loaded", vim.log.levels.ERROR)
    end,
    filtered_files_picker = function()
      vim.notify("Telescope is not installed or loaded", vim.log.levels.ERROR)
    end,
  }
end

local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

function M.saved_filters_picker()
  api.list_filters(function(filters)
    if type(filters) ~= "table" then filters = {} end
    
    if #filters == 0 then
      vim.notify("tagr: No saved filters found. Create one using 'tagr filter save <name>'", vim.log.levels.INFO)
      return
    end

    pickers.new({}, {
      prompt_title = "Tagr Saved Filters",
      finder = finders.new_table({
        results = filters,
        entry_maker = function(entry)
          return {
            value = entry,
            display = string.format("%-20s │ %s", entry.name, entry.description or "No description"),
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.value then
            M.filtered_files_picker(selection.value.name)
          end
        end)
        return true
      end,
    }):find()
  end)
end

function M.filtered_files_picker(filter_name)
  api.search({ "-F", filter_name }, function(files)
    if type(files) ~= "table" then files = {} end
    
    if #files == 0 then
      vim.notify("tagr: No files matched filter '" .. filter_name .. "'", vim.log.levels.INFO)
      return
    end

    pickers.new({}, {
      prompt_title = "Files matching: " .. filter_name,
      finder = finders.new_table({
        results = files,
        entry_maker = function(entry)
          local display_label = string.format("%s [%s]", vim.fs.basename(entry.file), table.concat(entry.tags, ", "))
          return {
            value = entry.file,
            display = display_label,
            ordinal = entry.file,
          }
        end,
      }),
      previewer = conf.file_previewer({}),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          end
        end)
        return true
      end,
    }):find()
  end)
end

-- Telescope Picker listing files of a specfic Tag input
function M.tag_search_picker()
  local pickers_dep = require("telescope.pickers")
  api.list("tags", function(tags_list)
    if type(tags_list) ~= "table" then tags_list = {} end

    if #tags_list == 0 then
      vim.notify("tagr: No tags found in database", vim.log.levels.INFO)
      return
    end

    pickers_dep.new({}, {
      prompt_title = "Select Tag",
      finder = finders.new_table({
        results = tags_list,
        entry_maker = function(entry)
          return {
            value = entry.name,
            display = string.format("%-25s (%d files)", entry.name, entry.file_count),
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            -- Pass back to unified picker wrapper
            local picker = require("tagr.picker")
            picker.files_by_tag_picker(selection.value)
          end
        end)
        return true
      end,
    }):find()
  end)
end

-- Find all files matching a specific tag value and allow fuzzy selecting
function M.files_by_tag_picker(tag_name)
  api.search({ "-t", tag_name }, function(files)
    if type(files) ~= "table" then files = {} end

    if #files == 0 then
      vim.notify("tagr: No files with tag '" .. tag_name .. "'", vim.log.levels.INFO)
      return
    end

    pickers.new({}, {
      prompt_title = "Files matching: #" .. tag_name,
      finder = finders.new_table({
        results = files,
        entry_maker = function(entry)
          local display_label = string.format("%s \t[%s]", vim.fs.basename(entry.file), table.concat(entry.tags, ", "))
          return {
            value = entry.file,
            display = display_label,
            ordinal = entry.file,
          }
        end,
      }),
      previewer = conf.file_previewer({}),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
          end
        end)
        return true
      end,
    }):find()
  end)
end

return M
