-- Headless tests for the diff parser and SHA1 (used to build GitLab line codes
-- for multi-line inline comments).
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/diff_spec.lua"

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local diff = require("glab-review.diff")
local util = require("glab-review.util")

local failures = 0
local function check(name, cond)
  io.write((cond and "ok   - " or "FAIL - ") .. name .. "\n")
  if not cond then
    failures = failures + 1
  end
end

-- SHA1 regression vectors.
check("sha1(abc)", util.sha1("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
check("sha1(empty)", util.sha1("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709")

-- A diff with a deletion, two additions, and surrounding context.
--   old: 1 line1, 2 old2, 3 line3, 4 line4
--   new: 1 line1, 2 new2, 3 new2b, 4 line3, 5 line4
local d = table.concat({
  "@@ -1,4 +1,5 @@",
  " line1",
  "-old2",
  "+new2",
  "+new2b",
  " line3",
  " line4",
}, "\n")

local map = diff.new_line_map(d)
check("context line1 -> old 1", map[1] == 1)
check("added new2 -> old 3", map[2] == 3)
check("added new2b -> old 3", map[3] == 3)
check("context line3 -> old 3", map[4] == 3)
check("context line4 -> old 4", map[5] == 4)

-- Multiple hunks accumulate independently.
local d2 = table.concat({
  "@@ -10,2 +10,2 @@",
  " a",
  " b",
  "@@ -50,1 +50,2 @@",
  " c",
  "+added",
}, "\n")
local map2 = diff.new_line_map(d2)
check("hunk2 context c -> old 50", map2[50] == 50)
check("hunk2 added -> old 51", map2[51] == 51)
check("line outside any hunk is absent", map2[999] == nil)

if failures > 0 then
  io.write(("\n%d failure(s)\n"):format(failures))
  vim.cmd("cquit 1")
else
  io.write("\nall passed\n")
  vim.cmd("quit")
end
