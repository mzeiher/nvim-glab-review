-- Headless test of how pending draft notes are classified and of the
-- draft/post decision a command's bang makes.
-- Run from the repo root with `make test`, or directly:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/draft_spec.lua"
-- Exits non-zero on failure.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local state = require("glab-review.state")

local failures = 0
local function check(name, cond)
  if cond then
    io.write("ok   - " .. name .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. name .. "\n")
  end
end

local mr = { iid = 42, diff_refs = { base_sha = "b", head_sha = "h", start_sha = "s" } }

local discussions = {
  {
    id = "thread1",
    resolvable = true,
    resolved = false,
    notes = { { id = 1, body = "posted", author = { username = "alice" } } },
  },
}

local drafts = {
  { id = 5, note = "on a line", position = { new_path = "lua/a.lua", new_line = 12 } },
  { id = 6, note = "staged reply", discussion_id = "thread1", resolve_discussion = true },
  -- A general draft: GitLab still sends a position object, with every field nil.
  { id = 7, note = "overall fine", position = { position_type = "text", new_path = vim.NIL } },
  -- A reply that also carries its thread's position belongs under the thread.
  {
    id = 8,
    note = "reply on a line",
    discussion_id = "thread1",
    position = { new_path = "lua/a.lua", new_line = 12 },
  },
}

state.load(mr, discussions, nil, drafts)

check("all drafts counted", state.draft_count() == 4)
check("drafts() keeps API order", state.drafts()[1].id == 5)
check("positioned draft indexed by path", #state.drafts_for_path("lua/a.lua") == 1)
check("positioned draft keeps its line", state.drafts_for_path("lua/a.lua")[1].line == 12)
check("replies indexed by discussion", #state.draft_replies("thread1") == 2)
check("staged resolve preserved", state.draft_replies("thread1")[1].resolve_discussion == true)
check("a positioned reply stays a reply", state.draft_replies("thread1")[2].id == 8)

check("an unpositioned draft is in neither index", #state.drafts_for_path("lua/a.lua") == 1)

check("no drafts for an untouched path", #state.drafts_for_path("lua/b.lua") == 0)
check("no replies for an unknown thread", #state.draft_replies("nope") == 0)

-- The resolved-thread filter must not reach drafts: they are never resolvable.
state.set_hide_resolved(true)
check("hide_resolved leaves drafts alone", #state.drafts_for_path("lua/a.lua") == 1)
state.set_hide_resolved(false)

-- A bang inverts the session mode, so it always means "the other way".
state.set_draft_mode(true)
check("mode on, no bang drafts", state.drafting(false) == true)
check("mode on, bang posts", state.drafting(true) == false)
check("mode on, nil bang drafts", state.drafting(nil) == true)
state.set_draft_mode(false)
check("mode off, no bang posts", state.drafting(false) == false)
check("mode off, bang drafts", state.drafting(true) == true)

-- Loading an MR without the endpoint (or without drafts) must stay empty.
state.load(mr, discussions, nil, nil)
check("no drafts loads clean", state.draft_count() == 0)
check("no drafts, no replies", #state.draft_replies("thread1") == 0)

-- How a body + its meta-commands are sent. Both the reply prompt and the
-- overview's `:w` route through this, so the truth table is the contract.
local reactions = require("glab-review.reactions")
local RESOLVE, UNRESOLVE = { resolve = true }, { resolve = false }
local DRAFT, POST = { draft = true }, { draft = false }
local AWARD = { award = "thumbsup" }

local p = reactions.plan("looks good", { RESOLVE }, true)
check("a drafted reply carries its resolve", p.staged == true and p.draft == true)

-- Regression: with no body to carry it, a staged resolve would be dropped by
-- both senders and the user told the thread was resolved.
p = reactions.plan("", { RESOLVE }, true)
check("a lone /resolve is not staged", p.staged == false)
check("a lone /resolve still acts", p.actionable == true and p.resolve == true)

p = reactions.plan("text", { RESOLVE }, false)
check("posting never stages", p.staged == false)
p = reactions.plan("text", { RESOLVE, POST }, true)
check("/post overrides the mode", p.draft == false and p.staged == false)
p = reactions.plan("text", { RESOLVE, DRAFT }, false)
check("/draft overrides the mode", p.draft == true and p.staged == true)
p = reactions.plan("text", { UNRESOLVE }, true)
check("an unresolve is never staged", p.staged == false and p.resolve == false)

-- Regression: a block whose only meta cannot act is not a change to push.
check("a lone /draft is not actionable", reactions.plan("", { DRAFT }, true).actionable == false)
check("an award alone is actionable", reactions.plan("", { AWARD }, true).actionable == true)
check("a body alone is actionable", reactions.plan("hi", {}, true).actionable == true)
check("no metas keeps the mode", reactions.plan("hi", {}, true).draft == true)
check("nothing at all is inert", reactions.plan("", {}, true).actionable == false)

if failures > 0 then
  io.write(("\n%d failure(s)\n"):format(failures))
  vim.cmd("cquit 1")
else
  io.write("\nall passed\n")
  vim.cmd("quit")
end
