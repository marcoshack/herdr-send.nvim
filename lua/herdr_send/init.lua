-- herdr-send.nvim: send code references and questions from Neovim to a coding
-- agent running in the same Herdr app tab, through herdr-core's `hc` CLI.

local M = {}

M.config = {
  -- Key for :HerdrAsk in normal and visual mode. Set to false for no mapping.
  keymap = "<leader>a",
  -- Sent when you leave the question empty.
  default_question = "Explain this code.",
  -- The `hc` binary.
  hc = "hc",
}

local function notify(msg, level)
  vim.schedule(function()
    vim.notify("herdr-send: " .. msg, level or vim.log.levels.INFO)
  end)
end

-- Run `hc` with args and decode its JSON output. Calls cb(result) on success;
-- reports errors itself.
local function hc_json(args, cb)
  vim.system(vim.list_extend({ M.config.hc }, args), { text = true }, function(res)
    if res.code ~= 0 then
      return notify(vim.trim(res.stderr ~= "" and res.stderr or res.stdout), vim.log.levels.ERROR)
    end
    local ok, decoded = pcall(vim.json.decode, res.stdout)
    if not ok then
      return notify("could not parse `hc` output", vim.log.levels.ERROR)
    end
    cb(decoded)
  end)
end

-- Pure: agents from an `hc ls --json` result, excluding our own terminal.
-- Agents are the terminals that report a status (OSC 7501).
function M._agents(listing, self_address)
  local agents = {}
  for _, t in ipairs(listing.terminals or {}) do
    if t.status ~= nil and t.address ~= self_address then
      table.insert(agents, t)
    end
  end
  return agents
end

-- Find the agent in this Herdr tab and call cb(address). Asks when there are several.
local function find_agent(cb)
  local self_address = vim.env.HC_TERMINAL_ID
  if not self_address then
    return notify("not running inside a Herdr app terminal ($HC_TERMINAL_ID is unset)", vim.log.levels.ERROR)
  end
  hc_json({ "get", "--json", self_address }, function(me)
    local tab = me.labels and me.labels["herdr.tab"]
    if not tab then
      return notify("this terminal has no Herdr tab", vim.log.levels.ERROR)
    end
    hc_json({ "ls", "--json", "--label", "herdr.tab=" .. tab }, function(listing)
      local agents = M._agents(listing, self_address)
      if #agents == 0 then
        return notify("no agent in this tab", vim.log.levels.WARN)
      end
      if #agents == 1 then
        return cb(agents[1].address)
      end
      vim.schedule(function()
        vim.ui.select(agents, {
          prompt = "Send to agent",
          format_item = function(t)
            return string.format("%s  %s (%s)", t.address, t.agent or "?", t.status)
          end,
        }, function(choice)
          if choice then
            cb(choice.address)
          end
        end)
      end)
    end)
  end)
end

-- Send text to the agent in this tab. `hc send` pastes it and presses Enter.
function M.send(text)
  find_agent(function(address)
    vim.system({ M.config.hc, "send", address, text }, { text = true }, function(res)
      if res.code ~= 0 then
        return notify(vim.trim(res.stderr ~= "" and res.stderr or res.stdout), vim.log.levels.ERROR)
      end
      notify("sent to " .. address)
    end)
  end)
end

-- Pure: the message for a question about lines first..last (1-based) of path,
-- with the diagnostics found there.
function M._message(question, path, first, last, diagnostics)
  local where = first == last and string.format("%s:%d", path, first)
    or string.format("%s:%d-%d", path, first, last)
  local lines = { question, "", "Code: " .. where }
  if #diagnostics > 0 then
    table.insert(lines, "Diagnostics:")
    for _, d in ipairs(diagnostics) do
      local severity = vim.diagnostic.severity[d.severity] or "?"
      table.insert(lines, string.format("- line %d, %s: %s", d.lnum + 1, severity:lower(), d.message))
    end
  end
  return table.concat(lines, "\n")
end

-- Ask the agent about lines first..last of the current buffer.
function M.ask(first, last)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.fn.expand("%:.")
  if path == "" then
    return notify("buffer has no file", vim.log.levels.WARN)
  end
  local diagnostics = vim.tbl_filter(function(d)
    return d.lnum + 1 >= first and d.lnum + 1 <= last
  end, vim.diagnostic.get(bufnr))

  vim.ui.input({ prompt = "Ask agent: " }, function(question)
    if question == nil then
      return -- cancelled with <Esc>
    end
    if vim.trim(question) == "" then
      question = M.config.default_question
    end
    M.send(M._message(question, path, first, last, diagnostics))
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("HerdrAsk", function(cmd)
    M.ask(cmd.line1, cmd.line2)
  end, { range = true, desc = "Ask the Herdr agent in this tab about these lines" })

  vim.api.nvim_create_user_command("HerdrSend", function(cmd)
    M.send(cmd.args)
  end, { nargs = "+", desc = "Send text to the Herdr agent in this tab" })

  if M.config.keymap then
    vim.keymap.set("n", M.config.keymap, "<cmd>HerdrAsk<cr>", { desc = "Ask Herdr agent about this line" })
    vim.keymap.set("x", M.config.keymap, ":HerdrAsk<cr>", { desc = "Ask Herdr agent about the selection" })
  end
end

return M
