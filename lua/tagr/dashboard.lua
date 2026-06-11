local api = require("tagr.api")
local statusline = require("tagr.statusline")
local ui = require("tagr.ui")
local M = {}

-- Keep track of open inspector windows and state
local inspector_win = nil
local inspector_buf = nil
local active_filepath = nil
local active_tags = {}
local all_tags = {}
local active_note = nil
local selection_index = 1 -- Used to navigate tag checkboxes

M.config = {
  layout = "float", -- Default layout: "float" or "split"
  split_direction = "vertical", -- "vertical" (right split) or "horizontal" (bottom split)
  split_size = 42,  -- Width/Height size of split window
  notes = {
    enabled = true,
    max_entries = 1,  -- Number of newest entries to show
    max_lines = 4,    -- Maximum lines per entry to show
  }
}

-- Split note into distinct historical entries based on markdown horizontal dividers
local function get_note_entries(content)
  if not content or content == "" then return {} end
  local raw_entries = vim.split(content, "\n%-%-%-+\r?\n")
  local entries = {}
  for _, entry in ipairs(raw_entries) do
    local trimmed = vim.trim(entry)
    if trimmed ~= "" then
      table.insert(entries, trimmed)
    end
  end
  return entries
end

-- Draw the neat dashboard UI lines
local function redraw_inspector()
  if not inspector_buf or not vim.api.nvim_buf_is_valid(inspector_buf) then
    return
  end

  -- Set buffer as modifiable to draw content lines
  vim.api.nvim_buf_set_option(inspector_buf, "modifiable", true)

  local info_lines = {}
  table.insert(info_lines, "┌────────────────────────────────────────────────────────────────────────┐")
  table.insert(info_lines, "│                             TAGR DASHBOARD                             │")
  table.insert(info_lines, "└────────────────────────────────────────────────────────────────────────┘")
  table.insert(info_lines, "  File: " .. vim.fs.basename(active_filepath))
  table.insert(info_lines, "  Path: " .. active_filepath)
  table.insert(info_lines, "  ────────────────────────────────────────────────────────────────────────")
  table.insert(info_lines, "  TAG MANAGEMENT: (Press <Enter> to toggle, <j/k> to hover, <g/G> to jump)")
  table.insert(info_lines, "")

  -- Mapping tag selections with neat checkbox icons
  local start_tag_line = #info_lines + 1
  for i, tag in ipairs(all_tags) do
    local is_active = false
    for _, t in ipairs(active_tags) do
      if t == tag then
        is_active = true
        break
      end
    end

    local check_icon = is_active and "● [x] " or "○ [ ] "
    local hover_indicator = (i == selection_index) and "➔ " or "  "
    table.insert(info_lines, hover_indicator .. check_icon .. tag)
  end

  table.insert(info_lines, "  ────────────────────────────────────────────────────────────────────────")
  
  -- Render newest notes if configured and populated
  local show_notes = M.config.notes.enabled and active_note and active_note.content ~= ""
  local note_start_line = nil
  if show_notes then
    table.insert(info_lines, "  NEWEST NOTES:")
    table.insert(info_lines, "")
    
    local entries = get_note_entries(active_note.content)
    local max_entries = M.config.notes.max_entries or 1
    local max_lines = M.config.notes.max_lines or 4
    
    local entries_shown = 0
    note_start_line = #info_lines + 1
    for i = #entries, 1, -1 do
      if entries_shown >= max_entries then break end
      local entry = entries[i]
      local lines = vim.split(entry, "\n")
      
      for l_idx, line in ipairs(lines) do
        if l_idx > max_lines then
          table.insert(info_lines, "    ...")
          break
        end
        table.insert(info_lines, "    " .. line)
      end
      
      entries_shown = entries_shown + 1
      if entries_shown < max_entries and i > 1 then
        table.insert(info_lines, "    ────────────────────────")
      end
    end
    table.insert(info_lines, "  ────────────────────────────────────────────────────────────────────────")
  end

  table.insert(info_lines, "  ACTIONS:")
  table.insert(info_lines, "  <t> Interactive Add Tag  │  <e> Open Markdown Notes Editor")
  table.insert(info_lines, "  <q> Close Inspector      │  <Enter> Toggle Tag status")
  table.insert(info_lines, "└────────────────────────────────────────────────────────────────────────┘")

  vim.api.nvim_buf_set_lines(inspector_buf, 0, -1, false, info_lines)
  vim.api.nvim_buf_set_option(inspector_buf, "modifiable", false)

  -- Setup highlighting highlights dynamically
  -- Highlight file paths and headers
  local ns_id = vim.api.nvim_create_namespace("tagr_dashboard")
  vim.api.nvim_buf_clear_namespace(inspector_buf, ns_id, 0, -1)
  
  -- Style headers
  vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Title", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Directory", 3, 2, -1)
  vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Comment", 6, 0, -1)

  if note_start_line then
    -- Highlight "NEWEST NOTES:" header line
    vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Special", note_start_line - 2, 0, -1)
  end

  for i, _ in ipairs(all_tags) do
    local line_idx = start_tag_line - 1 + (i - 1)
    if i == selection_index then
      vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "CursorLine", line_idx, 0, -1)
    end
  end
end

function M.open_inspector()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("tagr.nvim: Cannot inspect unnamed buffers", vim.log.levels.WARN)
    return
  end

  active_filepath = filepath

  -- Fetch metadata and global tags list sequentially to prepare dataset
  api.get_file_info(filepath, function(info)
    active_tags = info and info.tags or {}
    active_note = info and info.note or nil
    
    api.list("tags", function(tags)
      all_tags = {}
      if type(tags) == "table" then
        for _, tag in ipairs(tags) do
          table.insert(all_tags, tag.name)
        end
      end
      
      -- If there are no tags globally, add generic items to populate the list
      if #all_tags == 0 then
        all_tags = { "todo", "docs", "working", "archived", "draft" }
      end

      -- Sort tags alphabetically
      table.sort(all_tags)
      selection_index = 1

      -- Check and handle active buffers to close any existing ones first
      if inspector_win and vim.api.nvim_win_is_valid(inspector_win) then
        pcall(vim.api.nvim_win_close, inspector_win, true)
      end

      -- Launch buffer structure
      inspector_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(inspector_buf, "bufhidden", "wipe")
      vim.api.nvim_buf_set_option(inspector_buf, "filetype", "tagr_inspector")

      -- Compute maximum width to fit the content cleanly and prevent layout cutoff
      -- The dashboard text template has lines up to 76 characters, so use 76 as the absolute base minimum width.
      local base_template_width = 76
      local max_width = base_template_width
      for _, tag in ipairs(all_tags) do
        -- Account for the selection arrows, checkbox space, and margins (approx 10 chars)
        local line_len = #tag + 10
        if line_len > max_width then
          max_width = line_len
        end
      end
      -- Ensure margins fit a reasonable threshold size but at least 76 chars to prevent cutoffs
      max_width = math.max(max_width, math.min(base_template_width, math.floor(vim.o.columns * 0.95)))

      local layout_mode = M.config.layout
      if layout_mode == "split" then
        -- Handle Split Buffer rendering
        local split_cmd = M.config.split_direction == "vertical" and "botright vsplit" or "botright split"
        vim.cmd(split_cmd)
        
        -- Resize split window dynamically to fit the content precisely if split is vertical
        local win = vim.api.nvim_get_current_win()
        if M.config.split_direction == "vertical" then
          -- Auto-adjust split width to prevent visual truncation
          vim.api.nvim_win_set_width(win, max_width)
        else
          vim.api.nvim_win_set_height(win, M.config.split_size)
        end
        
        -- Load buffer into current opened split
        vim.api.nvim_win_set_buf(win, inspector_buf)
        inspector_win = win
      -- Default Floating layout
      else
        -- Pre-load lines to compute dynamically adapted window height perfectly
        redraw_inspector()
        local rendered_lines = vim.api.nvim_buf_get_lines(inspector_buf, 0, -1, false)

        local width = max_width
        local height = #rendered_lines
        local win_height = math.min(height, math.floor(vim.o.lines * 0.85))

        inspector_win = vim.api.nvim_open_win(inspector_buf, true, {
          relative = "editor",
          width = width,
          height = win_height,
          col = math.floor((vim.o.columns - width) / 2),
          row = math.floor((vim.o.lines - win_height) / 2),
          style = "minimal",
          border = "rounded",
          title = " Tagr Metadata Inspector ",
          title_pos = "center",
        })
      end

      -- Set default view parameters
      vim.api.nvim_buf_set_option(inspector_buf, "buftype", "nofile")
      
      redraw_inspector()

      -- Helper actions keymappings inside Dashboard Panel
      local function map_key(mode, key, rhs, desc)
        vim.keymap.set(mode, key, rhs, { buffer = inspector_buf, silent = true, desc = desc })
      end

      -- Move selection downwards
      map_key("n", "j", function()
        selection_index = math.min(selection_index + 1, #all_tags)
        redraw_inspector()
      end, "Dashboard: Hover Next Tag")

      -- Move selection upwards
      map_key("n", "k", function()
        selection_index = math.max(selection_index - 1, 1)
        redraw_inspector()
      end, "Dashboard: Hover Previous Tag")

      -- Jump to the first tag in the list (g)
      map_key("n", "g", function()
        selection_index = 1
        redraw_inspector()
      end, "Dashboard: Jump to first tag")
      map_key("n", "gg", function()
        selection_index = 1
        redraw_inspector()
      end, "Dashboard: Jump to first tag")

      -- Jump to the last tag in the list (G)
      map_key("n", "G", function()
        selection_index = #all_tags
        redraw_inspector()
      end, "Dashboard: Jump to last tag")

      -- Toggle selected Tag
      map_key("n", "<CR>", function()
        local target_tag = all_tags[selection_index]
        local is_already_tagged = false
        for _, t in ipairs(active_tags) do
          if t == target_tag then
            is_already_tagged = true
            break
          end
        end

        if is_already_tagged then
          -- Untag action
          api.remove_tags(active_filepath, { target_tag }, function()
            -- Remove from active tags array
            local filter_tags = {}
            for _, t in ipairs(active_tags) do
              if t ~= target_tag then
                table.insert(filter_tags, t)
              end
            end
            active_tags = filter_tags
            redraw_inspector()
            vim.cmd("silent! doautocmd User TagrUpdate")
          end)
        else
          -- Tag action
          api.add_tags(active_filepath, { target_tag }, function()
            table.insert(active_tags, target_tag)
            redraw_inspector()
            vim.cmd("silent! doautocmd User TagrUpdate")
          end)
        end
      end, "Dashboard: Toggle Tag status")

      -- Quick Add Custom Tag
      map_key("n", "t", function()
        -- Safely prompt for a new custom tag and append
        vim.ui.input({ prompt = "Insert custom tag: " }, function(input)
          if not input or input == "" then return end
          local raw_tag = vim.trim(input)
          if raw_tag ~= "" then
            api.add_tags(active_filepath, { raw_tag }, function()
              -- Add to dataset
              table.insert(active_tags, raw_tag)
              
              local found_in_global = false
              for _, gt in ipairs(all_tags) do
                if gt == raw_tag then found_in_global = true; break end
              end
              if not found_in_global then
                table.insert(all_tags, raw_tag)
                table.sort(all_tags)
              end
              
              redraw_inspector()
              vim.cmd("silent! doautocmd User TagrUpdate")
            end)
          end
        end)
      end, "Dashboard: Interactive Add tag")

      -- Launch details notes editor
      map_key("n", "e", function()
        -- Handle both split window or floating layout deletions gracefully on Note editing transition
        local is_split = M.config.layout == "split"
        if is_split then
          vim.cmd("close") -- Closes split window
        else
          pcall(vim.api.nvim_win_close, inspector_win, true)
        end
        ui.edit_note(active_filepath)
      end, "Dashboard: Launch Notes Editor")

      -- Close window
      map_key("n", "q", function()
        local is_split = M.config.layout == "split"
        if is_split then
          vim.cmd("close")
        else
          pcall(vim.api.nvim_win_close, inspector_win, true)
        end
      end, "Dashboard: Close Panel")

      map_key("n", "<ESC>", function()
        local is_split = M.config.layout == "split"
        if is_split then
          vim.cmd("close")
        else
          pcall(vim.api.nvim_win_close, inspector_win, true)
        end
      end, "Dashboard: Close Panel")
    end)
  end)
end

return M
