# herdr-send.nvim

Ask the coding agent next to your editor about the code under your cursor.

When Neovim runs inside the [Herdr app](https://herdr.dev), this plugin finds the
agent (Claude Code, Codex, ...) in the same Herdr tab and sends it a question with
the file, line range and any diagnostics on those lines, using herdr-core's `hc send`.

```
why does this fail?

Code: src/main.rs:12-20
Diagnostics:
- line 14, error: mismatched types expected `i32`, found `&str`
```

The agent reads the file itself, so only the reference is sent, not the code.

## Requirements

- Neovim 0.10+
- The Herdr app with herdr-core (`hc` on `PATH`). This is the desktop app, not the Herdr TUI.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "marcoshack/herdr-send.nvim",
  config = function()
    require("herdr_send").setup()
  end,
}
```

## Usage

| | |
|---|---|
| `<leader>a` (normal) | Ask about the current line |
| `<leader>a` (visual) | Ask about the selected lines |
| `:[range]HerdrAsk` | Same, as a command |
| `:HerdrSend {text}` | Send text as is |

Leave the question empty to send `Explain this code.`. If the tab has more than one
agent, you pick one.

## Options

```lua
require("herdr_send").setup({
  keymap = "<leader>a",                     -- false for no mapping
  default_question = "Explain this code.",
  hc = "hc",                                -- path to the hc binary
})
```

## How it works

1. `hc get $HC_TERMINAL_ID` gives Neovim's own terminal and its `herdr.tab` label.
2. `hc ls --label herdr.tab=<tab>` lists that tab's terminals. Agents are the ones
   reporting a status.
3. `hc send <agent> <text>` pastes the message and presses Enter. It waits if you
   have an unfinished draft in the agent, and refuses if the agent is blocked on
   a question.
