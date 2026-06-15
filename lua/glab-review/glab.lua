-- Thin async wrapper around the `glab api` CLI.
--
-- All requests go through the GitLab REST API via `glab`, which supplies host
-- and token resolution and substitutes the `:fullpath` placeholder from the
-- current git repo. Request bodies are passed as raw JSON on stdin (`--input -`)
-- so arbitrary comment text needs no shell escaping.
local util = require("glab-review.util")

local M = {}

local function glab_cmd()
  return require("glab-review.config").get().glab_cmd
end

--- Perform a `glab api` request.
--- @param path string  e.g. "projects/:fullpath/merge_requests?state=opened"
--- @param opts table|nil  { method = "GET"|"POST"|"PUT"|"DELETE", body = table|nil, paginate = bool }
--- @param cb fun(err: string|nil, data: any)  called with decoded JSON (scheduled)
function M.api(path, opts, cb)
  opts = opts or {}
  local cmd = { glab_cmd(), "api", path }
  local method = opts.method or (opts.body and "POST" or "GET")
  if method ~= "GET" then
    table.insert(cmd, "--method")
    table.insert(cmd, method)
  end
  if opts.paginate then
    table.insert(cmd, "--paginate")
  end

  local sys_opts = { text = true }
  if opts.body ~= nil then
    table.insert(cmd, "--input")
    table.insert(cmd, "-")
    sys_opts.stdin = vim.json.encode(opts.body)
  end

  local done = vim.schedule_wrap(function(out)
    if out.code ~= 0 then
      local msg = (out.stderr ~= "" and out.stderr or out.stdout or "glab api failed")
      cb(("glab api %s failed: %s"):format(path, (msg or ""):gsub("%s+$", "")), nil)
      return
    end
    local body = out.stdout or ""
    if body:gsub("%s", "") == "" then
      cb(nil, nil)
      return
    end
    local ok, decoded = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
    if not ok then
      cb("failed to decode glab response: " .. tostring(decoded), nil)
      return
    end
    cb(nil, decoded)
  end)

  vim.system(cmd, sys_opts, done)
end

--- Coroutine-friendly variant for use inside `util.async`. Returns (err, data).
function M.api_await(path, opts)
  return util.await(function(resume)
    M.api(path, opts, resume)
  end)
end

return M
