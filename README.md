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
    "GlabReviewComments",
    "GlabReviewChanged",
    "GlabReviewReact",
    "GlabReviewComment",
    "GlabReviewReply",
  },
  keys = {
    { "<leader>gms", "<cmd>GlabReviewSync<cr>",         desc = "glab: sync MRs" },
    { "<leader>gmo", "<cmd>GlabReviewOverview<cr>",     desc = "glab: overview" },
    { "<leader>gmt", "<cmd>GlabReviewToggleInline<cr>", desc = "glab: toggle inline" },
    { "<leader>gmc", "<cmd>GlabReviewComments<cr>",     desc = "glab: comments" },
    { "<leader>gmf", "<cmd>GlabReviewChanged<cr>",      desc = "glab: changed files" },
    { "<leader>gmr", "<cmd>GlabReviewReact<cr>",        desc = "glab: react" },
    { "<leader>gmn", "<cmd>GlabReviewComment<cr>",      desc = "glab: new comment" },
    { "<leader>gmR", "<cmd>GlabReviewReply<cr>",        desc = "glab: reply" },
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
| `:GlabReviewComments` | `<leader>gmc` | Pick / jump to any comment |
| `:GlabReviewChanged` | `<leader>gmf` | Pick changed files: open or send to quickfix |
| `:GlabReviewReact` | `<leader>gmr` | React to the comment under the cursor |
| `:GlabReviewComment` | `<leader>gmn` | Create a new comment on the current line / Visual selection |
| `:GlabReviewReply` | `<leader>gmR` | Reply to the thread under the cursor |

### The overview buffer

The buffer is structured with hidden HTML-comment markers. You edit only inside
three kinds of region; everything else is read-only context:

- **Description** — edit the text between the description markers.
- **Reply** — type under a thread's `reply` marker to post a reply to that
  thread.
- **New comment** — type under the `New comment` section to open a new thread.

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

For example, replying with:

```
Looks good to me.
/react-check
/resolve
```

posts "Looks good to me.", awards a checkmark, and resolves the thread.

## Configuration

Defaults (override any subset):

```lua
require("glab-review").setup({
  glab_cmd = "glab",
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
  },
  inline = {
    virt_text_default = true,     -- show comment bodies on load
    sign_text = "▌",
    sign_hl = "DiagnosticSignInfo",
    virt_hl = "Comment",
    author_hl = "DiagnosticInfo",
  },
  -- Set `keymaps = false` to define your own.
  keymaps = {
    sync = "<leader>gms",
    overview = "<leader>gmo",
    toggle_inline = "<leader>gmt",
    comments = "<leader>gmc",
    changed = "<leader>gmf",
    react = "<leader>gmr",
    comment = "<leader>gmn",
    reply = "<leader>gmR",
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
