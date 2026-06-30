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

-- changed_lines: the deletion+two-additions diff above.
--   new: 1 line1(ctx) 2 new2(+) 3 new2b(+) 4 line3(ctx) 5 line4(ctx)
-- One line deleted, two added: first addition "changes" the deletion, the
-- second is a pure "add"; no leftover delete marker.
local cl = diff.changed_lines(d)
local function find_kind(list, ln)
  for _, s in ipairs(list) do
    if s.line == ln then
      return s.kind
    end
  end
  return nil
end
check("changed: line 2 is a change", find_kind(cl, 2) == "change")
check("changed: line 3 is an add", find_kind(cl, 3) == "add")
check("changed: context line 1 unmarked", find_kind(cl, 1) == nil)
check("changed: context line 4 unmarked", find_kind(cl, 4) == nil)
check("changed: total signs == 2", #cl == 2)

-- Pure deletion with no replacement -> a single delete marker anchored on the
-- new-side line that follows the removed content.
local ddel = table.concat({
  "@@ -1,3 +1,2 @@",
  " keep1",
  "-gone",
  " keep2",
}, "\n")
local cdel = diff.changed_lines(ddel)
check("delete: one sign", #cdel == 1)
check("delete: anchored on following new line 2", cdel[1].line == 2 and cdel[1].kind == "delete")

-- changedelete: more deletions than additions leaves a trailing delete marker.
local dcd = table.concat({
  "@@ -1,3 +1,1 @@",
  "-a",
  "-b",
  "+merged",
}, "\n")
local ccd = diff.changed_lines(dcd)
check("changedelete: addition at line 1 is a change", find_kind(ccd, 1) == "change")
check("changedelete: leftover deletion marked delete", find_kind(ccd, 2) == "delete")

if failures > 0 then
  io.write(("\n%d failure(s)\n"):format(failures))
  vim.cmd("cquit 1")
else
  io.write("\nall passed\n")
  vim.cmd("quit")
end
