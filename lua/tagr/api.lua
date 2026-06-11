local M = {}

-- Helper to safely find the tagr binary (falls back to "tagr")
M.bin_path = "tagr"

-- Initialize configuration path or environment overrides if needed
function M.setup(opts)
  opts = opts or {}
  if opts.bin_path then
    M.bin_path = opts.bin_path
  end
end

-- Utility to run tagr asynchronously and parse JSON output
function M.run_tagr(args, callback)
  -- Insert binary path
  table.insert(args, 1, M.bin_path)
  
  -- Use non-blocking Neovim system/spawn execution
  vim.system(args, { text = true }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        -- Suppress warning if checking file that hasn't been added to database yet
        if not (args[2] == "file" and args[3] == "show") then
          vim.notify("tagr.nvim error: " .. (obj.stderr or "Unknown error"), vim.log.levels.WARN)
        end
        if callback then
          callback(nil)
        end
      end)
      return
    end

    if callback then
      local stdout = obj.stdout or ""
      local parsed = nil
      -- Only parse as JSON if it looks like a JSON array or object
      local first_char = stdout:match("^%s*(%S)")
      if first_char == "{" or first_char == "[" then
        local success, result = pcall(vim.json.decode, stdout)
        if success then
          parsed = result
        end
      end
      
      vim.schedule(function()
        callback(parsed or stdout)
      end)
    end
  end)
end

-- Get tags and notes metadata for a specific file
function M.get_file_info(filepath, callback)
  M.run_tagr({ "file", "show", filepath, "--json" }, callback)
end

-- Add tags to a file
function M.add_tags(filepath, tags, callback)
  local args = { "tag", "-f", filepath, "-t" }
  for _, tag in ipairs(tags) do
    table.insert(args, tag)
  end
  M.run_tagr(args, callback)
end

-- Remove specific tags from a file
function M.remove_tags(filepath, tags, callback)
  local args = { "untag", "-f", filepath, "-t" }
  for _, tag in ipairs(tags) do
    table.insert(args, tag)
  end
  M.run_tagr(args, callback)
end

-- Query files via search expression
function M.search(query_args, callback)
  local args = { "search", "--json" }
  for _, arg in ipairs(query_args) do
    table.insert(args, arg)
  end
  M.run_tagr(args, callback)
end

-- List all files or tags
function M.list(variant, callback)
  M.run_tagr({ "list", variant, "--json" }, callback)
end

return M
