local api = require("tagr.api")
local statusline = require("tagr.statusline")
local ui = require("tagr.ui")
local M = {}

-- We cache inspector instances globally to reuse windows and prevent multiple competing panels.
local inspector_win = nil
local inspector_buf = nil
local active_filepath = nil
local active_tags = {}
local all_tags = {}
local active_note = nil
local selection_index = 1

M.config = {
  layout = "float", -- Default layout: "float" or "split"
  split_direction = "vertical", -- "vertical" (right split) or "horizontal" (bottom split)
  split_size = 42,  -- Width/Height size of split window
  pinned_tags = {}, -- Tags that should always appear prioritized at the top of the selection checkbox list
  notes = {
    enabled = true,
    max_entries = 1,  -- Number of newest entries to show
    max_lines = 4,    -- Maximum lines per entry to show
  }
}

local function get_glyph(key, default)
  local tagr_main = package.loaded["tagr"]
  if tagr_main and tagr_main.config and tagr_main.config.glyphs then
    return tagr_main.config.glyphs[key] or default
  end
  return default
end

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

local function redraw_inspector()
  if not inspector_buf or not vim.api.nvim_buf_is_valid(inspector_buf) then
    return
  end

  -- Enable editing momentarily to redraw the visual dashboard lines.
  vim.bo[inspector_buf].modifiable = true

  local info_lines = {}
  table.insert(info_lines, "┌────────────────────────────────────────────────────────────────────────┐")
  table.insert(info_lines, "│                             TAGR DASHBOARD                             │")
  table.insert(info_lines, "└────────────────────────────────────────────────────────────────────────┘")
  table.insert(info_lines, "  File: " .. vim.fs.basename(active_filepath))
  table.insert(info_lines, "  Path: " .. active_filepath)
  table.insert(info_lines, "  ────────────────────────────────────────────────────────────────────────")
  table.insert(info_lines, "  TAG MANAGEMENT: (Press <Enter> to toggle, <j/k> to hover, <g/G> to jump)")
  table.insert(info_lines, "")

  local start_tag_line = #info_lines + 1
  for i, tag in ipairs(all_tags) do
    local is_active = false
    for _, t in ipairs(active_tags) do
      if t == tag then
        is_active = true
        break
      end
    end

    local hover_val = get_glyph("hover", "->")
    local check_icon = is_active and (get_glyph("checked", "[x]") .. " ") or (get_glyph("unchecked", "[ ]") .. " ")
    local hover_indicator = (i == selection_index) and (hover_val .. " ") or string.rep(" ", vim.fn.strdisplaywidth(hover_val) + 1)
    table.insert(info_lines, hover_indicator .. check_icon .. tag)
  end

  table.insert(info_lines, "  ────────────────────────────────────────────────────────────────────────")
  
  local show_notes = M.config.notes.enabled and type(active_note) == "table" and type(active_note.content) == "string" and active_note.content ~= ""
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
  vim.bo[inspector_buf].modifiable = false

  -- Clear namespace first to prevent multiple overlapping highlights over redraw iterations.
  local ns_id = vim.api.nvim_create_namespace("tagr_dashboard")
  vim.api.nvim_buf_clear_namespace(inspector_buf, ns_id, 0, -1)
  
  vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Title", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Directory", 3, 2, -1)
  vim.api.nvim_buf_add_highlight(inspector_buf, ns_id, "Comment", 6, 0, -1)

  if note_start_line then
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
    if type(info) ~= "table" then
      info = nil
    end
    active_tags = info and type(info.tags) == "table" and info.tags or {}
    active_note = info and type(info.note) == "table" and info.note or nil
    
    api.list("tags", function(tags)
      all_tags = {}
      if type(tags) == "table" then
        for _, tag in ipairs(tags) do
          table.insert(all_tags, tag.name)
        end
      end
      
      -- Providing predefined tags acts as an intuitive fallback if the overall database is empty.
      if #all_tags == 0 then
        all_tags = { "todo", "docs", "working", "archived", "draft" }
      end

      -- Sort non-pinned tags alphabetically, while preserving user defined order for pinned/favorite tags at the top.
      local pinned = M.config.pinned_tags or {}
      local pinned_map = {}
      local final_tags = {}
      
      for _, p_tag in ipairs(pinned) do
        table.insert(final_tags, p_tag)
        pinned_map[p_tag] = true
      end
      
      local other_tags = {}
      for _, t in ipairs(all_tags) do
        if not pinned_map[t] then
          table.insert(other_tags, t)
        end
      end
      table.sort(other_tags)
      
      for _, o_tag in ipairs(other_tags) do
        table.insert(final_tags, o_tag)
      end
      
      all_tags = final_tags
      selection_index = 1

      if inspector_win and vim.api.nvim_win_is_valid(inspector_win) then
        pcall(vim.api.nvim_win_close, inspector_win, true)
      end

      inspector_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[inspector_buf].bufhidden = "wipe"
      vim.bo[inspector_buf].filetype = "tagr_inspector"

      -- Computes target margins automatically to prevent word truncation across varying system screen boundaries.
      local base_template_width = 76
      local max_width = base_template_width
      for _, tag in ipairs(all_tags) do
        local line_len = #tag + 10
        if line_len > max_width then
          max_width = line_len
        end
      end
      max_width = math.max(max_width, math.min(base_template_width, math.floor(vim.o.columns * 0.95)))

      local layout_mode = M.config.layout
      if layout_mode == "split" then
        local split_cmd = M.config.split_direction == "vertical" and "botright vsplit" or "botright split"
        vim.cmd(split_cmd)
        
        local win = vim.api.nvim_get_current_win()
        if M.config.split_direction == "vertical" then
          vim.api.nvim_win_set_width(win, max_width)
        else
          vim.api.nvim_win_set_height(win, M.config.split_size)
        end
        
        vim.api.nvim_win_set_buf(win, inspector_buf)
        inspector_win = win
      else
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

      vim.bo[inspector_buf].buftype = "nofile"
      
      redraw_inspector()

      local function map_key(mode, key, rhs, desc)
        vim.keymap.set(mode, key, rhs, { buffer = inspector_buf, silent = true, desc = desc })
      end

      map_key("n", "j", function()
        selection_index = math.min(selection_index + 1, #all_tags)
        redraw_inspector()
      end, "Dashboard: Hover Next Tag")

      map_key("n", "k", function()
        selection_index = math.max(selection_index - 1, 1)
        redraw_inspector()
      end, "Dashboard: Hover Previous Tag")

      map_key("n", "g", function()
        selection_index = 1
        redraw_inspector()
      end, "Dashboard: Jump to first tag")
      map_key("n", "gg", function()
        selection_index = 1
        redraw_inspector()
      end, "Dashboard: Jump to first tag")

      map_key("n", "G", function()
        selection_index = #all_tags
        redraw_inspector()
      end, "Dashboard: Jump to last tag")

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
