local M = {}

M.bin_path = "tagr"

function M.setup(opts)
  opts = opts or {}
  if opts.bin_path then
    M.bin_path = opts.bin_path
  end
end

function M.run_tagr(args, callback)
  -- The tagr binary needs to be the first element when calling vim.system
  table.insert(args, 1, M.bin_path)
  
  -- vim.system is run in a separate system thread; main thread operations (like vim.notify
  -- or buffer updates) must be scheduled back to prevent race conditions or crashes.
  vim.system(args, { text = true }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        -- Querying a file that hasn't been parsed yet is a common non-exceptional flow,
        -- so we quiet the standard error logs for that specific path.
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
      -- Avoid JSON-decoding overhead and empty errors by checking the opening structure beforehand.
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

function M.get_file_info(filepath, callback)
  M.run_tagr({ "file", "show", filepath, "--json" }, callback)
end

function M.add_tags(filepath, tags, callback)
  local args = { "tag", "-f", filepath, "-t" }
  for _, tag in ipairs(tags) do
    table.insert(args, tag)
  end
  M.run_tagr(args, callback)
end

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

-- List all saved filter configurations
function M.list_filters(callback)
  M.run_tagr({ "filter", "list", "--json" }, callback)
end

return M
