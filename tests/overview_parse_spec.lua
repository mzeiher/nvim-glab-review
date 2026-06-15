-- Headless test of the save-protocol parser (the highest-risk logic).
-- Run from the repo root with `make test`, or directly:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/overview_parse_spec.lua"
-- Exits non-zero on failure.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local overview = require("glab-review.overview")

local failures = 0
local function check(name, cond)
  if cond then
    io.write("ok   - " .. name .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. name .. "\n")
  end
end

local function lines(s)
  return vim.split(s, "\n", { plain = true })
end

-- 1. A full buffer with a description edit, one thread reply, and a new comment.
local doc = table.concat({
  "# !42  Title",
  "opened · @alice · https://x/mr/42",
  "",
  "<!-- glab-review:description -->",
  "Updated description",
  "second line",
  "<!-- glab-review:end -->",
  "",
  "## Threads (1)",
  "",
  "<!-- glab-review:thread id=abc123 resolved=false resolvable=true -->",
  "### @bob · 2026-06-15",
  "Please rename this.",
  "",
  "<!-- glab-review:reply id=abc123 -->",
  "Done, renamed it.",
  "/resolve",
  "<!-- glab-review:end -->",
  "",
  "## New comment",
  "",
  "<!-- glab-review:new -->",
  "A brand new thread.",
  "<!-- glab-review:end -->",
}, "\n")

local r = overview.parse(lines(doc))

check("description captured", r.description and r.description.body == "Updated description\nsecond line")
check("one reply captured", #r.replies == 1)
check("reply id parsed", r.replies[1] and r.replies[1].id == "abc123")
check("reply body includes meta line raw", r.replies[1].body == "Done, renamed it.\n/resolve")
check("new comment captured", r.new and r.new.body == "A brand new thread.")

-- 2. Empty input regions yield empty bodies (caller skips them).
local empty = table.concat({
  "<!-- glab-review:description -->",
  "<!-- glab-review:end -->",
  "<!-- glab-review:thread id=z9 resolved=true resolvable=true -->",
  "### @carol · 2026-06-15",
  "existing",
  "<!-- glab-review:reply id=z9 -->",
  "<!-- glab-review:end -->",
  "<!-- glab-review:new -->",
  "<!-- glab-review:end -->",
}, "\n")

local r2 = overview.parse(lines(empty))
check("empty description body", r2.description and r2.description.body == "")
check("empty reply body", #r2.replies == 1 and r2.replies[1].body == "")
check("empty new body", r2.new and r2.new.body == "")

-- 3. Thread header/body content is never captured as input.
check("existing note text ignored", not (r2.replies[1].body):find("existing"))

-- 4. Meta extraction splits commands from body.
local reactions = require("glab-review.reactions")
require("glab-review.config").setup({})
local body, metas = reactions.extract_metas("Looks good\n/react-check\n/resolve")
check("meta body cleaned", body == "Looks good")
check("two metas extracted", #metas == 2)
check("award meta", metas[1].award == "white_check_mark")
check("resolve meta", metas[2].resolve == true)

if failures > 0 then
  io.write(("\n%d failure(s)\n"):format(failures))
  vim.cmd("cquit 1")
else
  io.write("\nall passed\n")
  vim.cmd("quit")
end
