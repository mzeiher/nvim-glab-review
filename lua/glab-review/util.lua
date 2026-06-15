-- Small helpers: async (coroutine) flow control, git/branch lookup, notifications.
local M = {}

local unpack = table.unpack or unpack

local PREFIX = "[glab-review] "

function M.notify(msg, level)
  vim.schedule(function()
    vim.notify(PREFIX .. msg, level or vim.log.levels.INFO)
  end)
end

function M.err(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

--- Run `fn` as a coroutine so that `M.await(...)` can be used inside it to
--- linearise callback-based async APIs. Any error raised inside the coroutine
--- is surfaced as a notification instead of being silently swallowed.
function M.async(fn)
  return function(...)
    local args = { ... }
    local co = coroutine.create(function()
      local ok, e = pcall(fn, unpack(args))
      if not ok then
        M.err(tostring(e))
      end
    end)
    local ok, e = coroutine.resume(co)
    if not ok then
      M.err(tostring(e))
    end
  end
end

--- Inside an `M.async` coroutine, suspend until `starter(resume)` invokes its
--- callback, then return whatever was passed to that callback.
--- Works whether the callback fires synchronously or later.
function M.await(starter)
  local co = coroutine.running()
  assert(co, "M.await must be called inside M.async")
  local result, sync_done = nil, false
  starter(function(...)
    result = { ... }
    if coroutine.status(co) == "suspended" then
      -- Callback fired after we yielded: resume to continue the flow.
      local ok, e = coroutine.resume(co)
      if not ok then
        M.err(tostring(e))
      end
    else
      -- Callback fired synchronously, before we yielded.
      sync_done = true
    end
  end)
  if not sync_done then
    coroutine.yield()
  end
  return unpack(result or {})
end

--- Current git branch for `cwd` (defaults to the editor cwd). Returns nil on error.
function M.git_branch()
  local out = vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait()
  if out.code ~= 0 then
    return nil, (out.stderr or "git failed"):gsub("%s+$", "")
  end
  return (out.stdout or ""):gsub("%s+$", "")
end

--- Repo root, used to resolve buffer paths to repo-relative paths.
function M.git_root()
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if out.code ~= 0 then
    return nil
  end
  return (out.stdout or ""):gsub("%s+$", "")
end

--- Map an absolute file path to a path relative to the repo root, using
--- forward slashes (matching GitLab paths). Returns nil when outside the repo.
function M.repo_relative(abspath, root)
  root = root or M.git_root()
  if not root or abspath == "" then
    return nil
  end
  abspath = vim.fs.normalize(abspath)
  root = vim.fs.normalize(root)
  if abspath == root then
    return nil
  end
  local prefix = root .. "/"
  if abspath:sub(1, #prefix) == prefix then
    return abspath:sub(#prefix + 1)
  end
  return nil
end

--- Percent-encode a string for use in a URL query value.
function M.urlencode(s)
  return (tostring(s):gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--- Truncate to a single line of at most `n` characters for picker/virt display.
function M.snippet(s, n)
  n = n or 60
  s = (s or ""):gsub("\r", ""):gsub("\n", " ↵ ")
  if #s > n then
    s = s:sub(1, n - 1) .. "…"
  end
  return s
end

return M
