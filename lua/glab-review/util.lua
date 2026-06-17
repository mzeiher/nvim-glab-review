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

--- SHA1 hash of a string, returned as a 40-char lowercase hex digest.
--- Used to build GitLab diff line codes (`<sha1(path)>_<old>_<new>`).
function M.sha1(msg)
  local bit = require("bit")
  local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
  local lshift, rol, tohex = bit.lshift, bit.rol, bit.tohex

  local h0, h1, h2, h3, h4 =
    0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

  local len = #msg
  msg = msg .. "\128"
  while (#msg % 64) ~= 56 do
    msg = msg .. "\0"
  end
  -- 64-bit big-endian bit length (high word is 0 for any realistic path)
  local bitlen, lenbytes = len * 8, {}
  for i = 8, 1, -1 do
    lenbytes[i] = string.char(bitlen % 256)
    bitlen = math.floor(bitlen / 256)
  end
  msg = msg .. table.concat(lenbytes)

  for chunk = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do
      local b1, b2, b3, b4 = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i] = bor(lshift(b1, 24), lshift(b2, 16), lshift(b3, 8), b4)
    end
    for i = 16, 79 do
      w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
      elseif i < 40 then
        f, k = bxor(bxor(b, c), d), 0x6ED9EBA1
      elseif i < 60 then
        f, k = bor(bor(band(b, c), band(b, d)), band(c, d)), 0x8F1BBCDC
      else
        f, k = bxor(bxor(b, c), d), 0xCA62C1D6
      end
      local temp = band(rol(a, 5) + f + e + k + w[i], 0xFFFFFFFF)
      e, d, c, b, a = d, c, rol(b, 30), a, temp
    end
    h0 = band(h0 + a, 0xFFFFFFFF)
    h1 = band(h1 + b, 0xFFFFFFFF)
    h2 = band(h2 + c, 0xFFFFFFFF)
    h3 = band(h3 + d, 0xFFFFFFFF)
    h4 = band(h4 + e, 0xFFFFFFFF)
  end

  return tohex(h0) .. tohex(h1) .. tohex(h2) .. tohex(h3) .. tohex(h4)
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
