# nvim-glab-review

> [!NOTE]
> **This plugin was written by AI (Claude), as a personal tool just for me.**
> It is a bespoke, single-user project — not a maintained or supported release.
> Expect no stability guarantees, no issue triage, and no backwards-compat
> promises. Use it at your own risk, and feel free to fork it for your own needs.

Review and manage GitLab Merge Request comments from inside Neovim, driven
entirely through the [`glab`](https://gitlab.com/gitlab-org/cli) CLI.

The workflow is **explicit sync**: you trigger a sync, pick the MR for your
current branch from an [fzf-lua](https://github.com/ibhagwan/fzf-lua) picker,
and the plugin loads its description and discussions. The description and
general threads open in an editable scratch buffer — writing and saving pushes
your changes. Inline (diff-positioned) comments appear as toggleable virtual
text with a gutter sign, just like diagnostics.

## Features

- **Sync per branch** — list open MRs whose source branch is the current branch
  and pick one (`:GlabReviewSync`).
- **Overview buffer** — the MR description (editable) plus every general thread.
  Save (`:w`) to push: edited description, replies to threads, brand-new
  comments, and `/meta-commands` (see below).
- **Inline comments** — gutter signs on commented lines and toggleable virtual
  text showing each thread's notes (`:GlabReviewToggleInline`).
- **Hide settled threads** — toggle resolved threads out of the gutter, the
  overview and the picker in one go, so only what still needs attention is on
  screen (`:GlabReviewToggleResolved`, or start that way with
  `hide_resolved = true`).
- **Change hints** — gitsigns-style gutter signs marking the lines the MR
  changed (added / changed / deleted) when you open a changed file. Only the
  affected lines are marked — there's no full-diff view
  (`:GlabReviewToggleChanges`). A delete sign also carries how many lines went
  away there (`▁3`), since removed content is nowhere in your working tree.
- **Removed lines** — see what the MR deleted, which exists nowhere in your
  working tree: as a float for the hunk under the cursor (`:GlabReviewHunk`), or
  inlined as virtual text above where it was (`:GlabReviewToggleRemoved`, off by
  default since it pushes the code down).
- **Hunk motions** — jump between the blocks the MR changed with `]h` / `[h`
  (counts work: `3]h`), wrapping at the end of the file.
- **Create inline comments** — always start a new thread on the line under the
  cursor (`:GlabReviewComment`). Select lines in Visual mode to post a single
  **multi-line** comment spanning the selection.
- **Reply to threads** — reply to the thread under the cursor, on a commented
  code line or a thread in the overview buffer (`:GlabReviewReply`).
- **Comment navigation** — fzf-lua picker over every comment that jumps to the
  file/line (inline) or the thread (general) (`:GlabReviewComments`).
- **Changed files** — fzf-lua picker over the files changed in the MR; open
  them or send the selection to the quickfix list (`:GlabReviewChanged`).
- **React** — award an emoji to the comment under the cursor via an fzf-lua
  picker (`:GlabReviewReact`).
- **Resolve** — every resolvable thread shows an `○ open` / `✓ resolved` hint
  (inline, overview, and comment picker); toggle the resolved state of the
  discussion under the cursor (`:GlabReviewResolve`).
- **Suggest** — turn the current line or a Visual selection into a GitLab
  suggestion (` ```suggestion ` block) the author can apply with one click;
  the replacement is edited in a scratch buffer and posted on `:w`
  (`:GlabReviewSuggest`).
- **Pending reviews** — new comments queue as GitLab draft notes instead of
  going out one at a time, exactly like "Start a review" in the web UI; they
  live on the server, so they survive a restart and show up in the browser as
  the same pending review. A bang inverts it for one command
  (`:GlabReviewComment!` posts straight through), `:GlabReviewToggleDraft`
  flips the mode, and `:GlabReviewDiscard` throws one away. A `/resolve` on a
  drafted reply in the overview is staged with it.
- **Submit** — hand the MR back with a verdict: approve (tied to the reviewed
  head commit), request changes, or a plain comment — plus unapprove to take
  an approval back. Anything still pending is published first, with the submit
  comment attached as the review's summary note; unapproving is the exception
  and leaves drafts pending (`:GlabReviewSubmit`).

## Requirements

- Neovim **0.10+**
- [`glab`](https://gitlab.com/gitlab-org/cli), authenticated (`glab auth login`)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- `git` (to determine the current branch and resolve buffer paths)

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim) — lazy-loaded on its
commands and keys:

```lua
{
  "mzeiher/nvim-glab-review",
  dependencies = { "ibhagwan/fzf-lua" },
  cmd = {
    "GlabReviewSync",
    "GlabReviewOverview",
    "GlabReviewToggleInline",
    "GlabReviewToggleResolved",
    "GlabReviewToggleChanges",
    "GlabReviewToggleRemoved",
    "GlabReviewHunk",
    "GlabReviewNextHunk",
    "GlabReviewPrevHunk",
    "GlabReviewComments",
    "GlabReviewChanged",
    "GlabReviewReact",
    "GlabReviewComment",
    "GlabReviewReply",
    "GlabReviewResolve",
    "GlabReviewSuggest",
    "GlabReviewSubmit",
  },
  keys = {
    { "<leader>gms", "<cmd>GlabReviewSync<cr>",         desc = "glab: sync MRs" },
    { "<leader>gmo", "<cmd>GlabReviewOverview<cr>",     desc = "glab: overview" },
    { "<leader>gmt", "<cmd>GlabReviewToggleInline<cr>", desc = "glab: toggle inline" },
    { "<leader>gmT", "<cmd>GlabReviewToggleResolved<cr>",desc = "glab: toggle resolved threads" },
    { "<leader>gmd", "<cmd>GlabReviewToggleChanges<cr>",desc = "glab: toggle change hints" },
    { "<leader>gmD", "<cmd>GlabReviewToggleRemoved<cr>",desc = "glab: toggle removed lines" },
    { "<leader>gmh", "<cmd>GlabReviewHunk<cr>",         desc = "glab: preview hunk at cursor" },
    { "]h",          "<cmd>GlabReviewNextHunk<cr>",     desc = "glab: next MR change" },
    { "[h",          "<cmd>GlabReviewPrevHunk<cr>",     desc = "glab: previous MR change" },
    { "<leader>gmc", "<cmd>GlabReviewComments<cr>",     desc = "glab: comments" },
    { "<leader>gmf", "<cmd>GlabReviewChanged<cr>",      desc = "glab: changed files" },
    { "<leader>gmr", "<cmd>GlabReviewReact<cr>",        desc = "glab: react" },
    { "<leader>gmn", "<cmd>GlabReviewComment<cr>",      desc = "glab: new comment" },
    { "<leader>gmR", "<cmd>GlabReviewReply<cr>",        desc = "glab: reply" },
    { "<leader>gmx", "<cmd>GlabReviewResolve<cr>",      desc = "glab: resolve/unresolve" },
    { "<leader>gmS", "<cmd>GlabReviewSuggest<cr>",      desc = "glab: suggest change" },
    { "<leader>gma", "<cmd>GlabReviewSubmit<cr>",       desc = "glab: submit review verdict" },
    { "<leader>gmP", "<cmd>GlabReviewToggleDraft<cr>",  desc = "glab: toggle drafting" },
    { "<leader>gmX", "<cmd>GlabReviewDiscard<cr>",      desc = "glab: discard pending comment" },
    { "<leader>gmS", "<cmd>GlabReviewSuggest<cr>", mode = "x", desc = "glab: suggest for selection" },
    { "<leader>gmn", "<cmd>GlabReviewComment<cr>", mode = "x", desc = "glab: comment on selection" },
  },
  opts = {},
}
```

`opts = {}` calls `require("glab-review").setup({})`. lazy.nvim resolves the
main module (`glab-review`) from the repo name automatically, so no `main`
field is needed. Pass a table to override any default (see
[Configuration](#configuration)).

> The default `setup()` also installs the `<leader>gm*` mappings above. If you
> lazy-load on `keys` as shown, set `opts = { keymaps = false }` to avoid
> defining them twice.

## Usage

1. Check out the branch of the MR you want to review (ideally at the MR's head
   commit — see [Inline comment mapping](#inline-comment-mapping)).
2. `:GlabReviewSync` → pick the MR. The overview buffer opens.
3. Open any changed file → inline comments show as gutter signs + virtual text.
4. `:GlabReviewComments` to jump around; `:GlabReviewReact` to react,
   `:GlabReviewReply` to reply, or `:GlabReviewComment` to start a new thread on
   a line.

### Commands

| Command | Default key | Action |
| --- | --- | --- |
| `:GlabReviewSync` | `<leader>gms` | List MRs for the branch and pick one |
| `:GlabReviewOverview` | `<leader>gmo` | Open the overview buffer |
| `:GlabReviewToggleInline` | `<leader>gmt` | Toggle inline comment bodies |
| `:GlabReviewToggleResolved` | `<leader>gmT` | Show / hide resolved threads everywhere |
| `:GlabReviewToggleChanges` | `<leader>gmd` | Toggle change-hint gutter signs |
| `:GlabReviewToggleRemoved` | `<leader>gmD` | Toggle the MR's removed lines shown inline |
| `:GlabReviewHunk` | `<leader>gmh` | Preview the MR diff hunk at the cursor (incl. removed lines) |
| `:GlabReviewNextHunk` | `]h` | Jump to the next block of changed lines (wraps, takes a count) |
| `:GlabReviewPrevHunk` | `[h` | Jump to the previous block of changed lines |
| `:GlabReviewComments` | `<leader>gmc` | Pick / jump to any comment |
| `:GlabReviewChanged` | `<leader>gmf` | Pick changed files: open or send to quickfix |
| `:GlabReviewReact` | `<leader>gmr` | React to the comment under the cursor |
| `:GlabReviewComment[!]` | `<leader>gmn` | Create a new comment on the current line / Visual selection (`!` inverts drafting) |
| `:GlabReviewReply[!]` | `<leader>gmR` | Reply to the thread under the cursor (`!` inverts drafting) |
| `:GlabReviewResolve` | `<leader>gmx` | Toggle resolved state of the discussion under the cursor |
| `:GlabReviewSuggest[!]` | `<leader>gmS` | Suggest a code change for the current line / Visual selection (`!` inverts drafting) |
| `:GlabReviewSubmit` | `<leader>gma` | Publish anything pending, then submit a verdict: approve, request changes, or comment |
| `:GlabReviewToggleDraft` | `<leader>gmP` | Toggle whether new comments queue as pending drafts |
| `:GlabReviewDiscard[!]` | `<leader>gmX` | Discard the pending comment at the cursor (`!` discards all) |

### The overview buffer

By default the overview opens in a vertical split. Set `overview.open` to
`"split"`, `"tab"` (new tab page), or `"current"` (reuse the current window) to
change this. If the overview is already visible — on any tab page — it's
focused instead of reopened.

The buffer is structured with hidden HTML-comment markers. You edit only inside
three kinds of region; everything else is read-only context:

- **Description** — edit the text between the description markers.
- **Reply** — type under a thread's `reply` marker to post a reply to that
  thread.
- **New comment** — type under the `New comment` section to open a new thread.

While drafting is on, a `Pending review` section lists everything queued and
where it will land. It is informational: `:w` ignores it, and drafts are not
editable there — discard one with `:GlabReviewDiscard` and write it again.

Save with `:w`. The plugin diffs the editable regions against what it rendered
and only pushes what changed, then re-syncs. Existing note bodies are read-only
(editing them has no effect — GitLab only lets you edit your own notes, which is
out of scope here).

### Meta-commands

Inside a reply region you can add command lines that are pulled out of the body
and dispatched as actions:

| Command | Effect |
| --- | --- |
| `/react-check` | Award ✅ (`white_check_mark`) to the thread's first note |
| `/react-up` | Award 👍 (`thumbsup`) |
| `/react-eyes` | Award 👀 (`eyes`) |
| `/resolve` | Resolve the thread |
| `/unresolve` | Unresolve the thread |
| `/draft` | Queue this block as a pending draft |
| `/post` | Post this block now, even while drafting |

The `:GlabReviewReply` and `:GlabReviewComment` prompts take them too and strip
every one from the body — several are live GitLab quick actions, so a `/draft`
reaching the note would mark the MR itself a draft. A brand-new comment has no
thread behind it, so only `/draft` and `/post` do anything there.

For example, replying with:

```
Looks good to me.
/react-check
/resolve
```

posts "Looks good to me.", awards a checkmark, and resolves the thread.

`/draft` and `/post` stand in for a command's bang, which `:w` cannot express.
On a drafted reply, a `/resolve` alongside reply text is staged with the draft:
the thread settles when the review is published, not when you save. With no
text to carry it — including at the single-line `:GlabReviewReply`
prompt — it resolves right away.

## Configuration

Defaults (override any subset):

```lua
require("glab-review").setup({
  glab_cmd = "glab",
  hide_resolved = false,         -- start with resolved threads hidden
  draft = true,                  -- queue new comments as pending drafts
  overview = {
    -- "vsplit" | "split" | "tab" | "current"
    open = "vsplit",
  },
  emojis = {
    "👍 thumbsup", "👎 thumbsdown", "✅ white_check_mark",
    "🎉 tada", "👀 eyes", "🚀 rocket", "❤️ heart", "🤔 thinking",
  },
  meta_commands = {
    ["/react-check"] = { award = "white_check_mark" },
    ["/react-up"]    = { award = "thumbsup" },
    ["/react-eyes"]  = { award = "eyes" },
    ["/resolve"]     = { resolve = true },
    ["/unresolve"]   = { resolve = false },
    ["/draft"]       = { draft = true },   -- queue this block
    ["/post"]        = { draft = false },  -- post it now
  },
  inline = {
    virt_text_default = true,     -- show comment bodies on load
    sign_text = "▌",
    sign_hl = "DiagnosticSignInfo",
    virt_hl = "Comment",
    author_hl = "DiagnosticInfo",
    draft_sign_text = "▐",       -- pending drafts, marked apart
    draft_sign_hl = "DiagnosticSignWarn",
    draft_hl = "DiagnosticWarn",
  },
  changes = {
    enabled = true,              -- show change hints on load
    add_sign = "▎",
    change_sign = "▎",
    delete_sign = "▁",
    add_hl = "DiagnosticSignOk",
    change_hl = "DiagnosticSignWarn",
    delete_hl = "DiagnosticSignError",
    delete_count = true,         -- append the removed-line count ("▁3")
    show_removed = false,        -- removed lines inline (shifts code down)
    removed_prefix = "- ",
    removed_hl = "DiffDelete",
  },
  -- Set `keymaps = false` to define your own.
  keymaps = {
    sync = "<leader>gms",
    overview = "<leader>gmo",
    toggle_inline = "<leader>gmt",
    toggle_resolved = "<leader>gmT",
    toggle_changes = "<leader>gmd",
    toggle_removed = "<leader>gmD",
    hunk = "<leader>gmh",
    next_hunk = "]h",            -- bracket keys: repeated often, count-aware
    prev_hunk = "[h",
    comments = "<leader>gmc",
    changed = "<leader>gmf",
    react = "<leader>gmr",
    comment = "<leader>gmn",
    reply = "<leader>gmR",
    resolve = "<leader>gmx",
    suggest = "<leader>gmS",
    submit = "<leader>gma",
    toggle_draft = "<leader>gmP",
    discard = "<leader>gmX",
  },
})
```

Each emoji entry is `"<display> <api_name>"`; only the last whitespace-separated
token (the GitLab award-emoji name) is sent.

## Inline comment mapping

Inline comments are anchored to a commit SHA + file + line in the MR diff. The
plugin maps them to your working buffer using the comment's `new_line` (or
`old_line` for deletion-side comments) **1:1**. This is accurate when your
working tree matches the MR's head commit. Comments that can't be resolved
(e.g. outdated comments against a superseded diff) are not placed in the gutter;
they're listed in the `:GlabReviewComments` picker (marked ⚠ outdated) and
counted in the load summary.

New inline comments created with `:GlabReviewComment` are anchored to the
current line on the new side of the diff; this works for lines present in the
MR diff's new revision.

## Seeing what the MR changed

You review the working tree, which only holds the **new** side of the diff: added
and changed lines are there to be marked, but lines the MR *removed* exist
nowhere in the buffer. Three layers cover that, quietest first — pick what you
want on and toggle the rest.

**1. The sign column** (always on, next to diagnostics):

| Sign | Meaning |
| --- | --- |
| `▎` (`add_hl`) | line added by the MR |
| `▎` (`change_hl`) | line that replaced a removed line |
| `▁3` (`delete_hl`) | 3 lines were removed here, nothing replaced them |

The count on the delete sign is the one piece of "invisible" information worth
having at a glance; set `changes.delete_count = false` for a bare marker.

**2. Hunk preview on demand** — `:GlabReviewHunk` shows the diff hunk around the
cursor in a floating window (`diff`-highlighted, so `-` lines read as removals).
Press it a second time to enter the float and scroll a long hunk; it closes as
soon as you move the cursor. The buffer is not touched.

**3. Removed lines inline** — `:GlabReviewToggleRemoved` renders the deleted text
as virtual lines above the spot it was removed from, prefixed with `- ` in
`DiffDelete`. This is the loud option: while it's on, code below each removal is
pushed down by as many lines as the MR deleted, so it's **off by default**. Start
it on with `changes.show_removed = true`, and restyle with
`changes.removed_prefix` / `changes.removed_hl`.

The gutter signs and the inline removed lines toggle independently — you can run
removed lines with `:GlabReviewToggleChanges` off for a bare before/after read.

To move between them, `]h` / `[h` jump to the next / previous block of changed
lines — consecutive changed lines count as one block, so you land once per change
rather than once per line. They wrap at the end of the file, take a count (`3]h`),
leave a jumplist entry (`<C-o>` comes back), echo `MR change 2/7` so you know
where you are, and work whether or not the signs are currently shown.

## Documentation

Full help is available in Neovim:

```vim
:help glab-review
```

## Development

```
nvim-glab-review/
├── doc/glab-review.txt        # :help glab-review
├── lua/glab-review/           # plugin modules (see :help glab-review-internals)
├── plugin/glab-review.lua     # user commands
├── tests/                     # headless tests
├── Makefile                   # `make test`, `make lint`, `make format`
├── .luarc.json .stylua.toml   # lua-language-server + stylua config
```

The save-protocol parser (`overview.parse`) is pure and unit-tested. Run the
suite with:

```sh
make test
```

Format and lint with [stylua](https://github.com/JohnnyMorganz/StyLua):

```sh
make format   # apply
make lint     # check only
```
