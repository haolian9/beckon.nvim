---design ghoices
---* no large datasets, or use fond instead
---* no cache, or use fond instead
---* one buffer and one window
---* the first line is for user input
---* the rest lines are matched results
---* no inline extmark as the prompt, which is buggy in my test
---* no i_c-n and i_c-p
---* no i_c-u and i_c-d
---* no fzf --nth
---
---todo: highlight tokens
---todo: distinguish i_cr, i_c-/, i_c-t, n_v, n_t, n_i, n_o

local augroups = require("infra.augroups")
local buflines = require("infra.buflines")
local Ephemeral = require("infra.Ephemeral")
local feedkeys = require("infra.feedkeys")
local jelly = require("infra.jellyfish")("beckon", "debug")
local bufmap = require("infra.keymap.buffer")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local wincursor = require("infra.wincursor")

local facts = require("beckon.facts")
local fuzzymatch = require("beckon.fuzzymatch")

local api = vim.api

local RHS
do
  ---@class beckon.RHS
  ---@field bufnr integer
  ---@field on_pick fun(line: string)
  local Impl = {}
  Impl.__index = Impl

  local function close_current_win()
    if api.nvim_get_mode().mode == "i" then feedkeys("<esc>", "n") end
    api.nvim_win_close(0, false)
  end

  function Impl:pick_cursor()
    local count = buflines.count(self.bufnr)
    if count == 1 then return jelly.debug("no match") end

    local lnum = wincursor.lnum()
    if lnum == 0 then return jelly.debug("not a match") end

    local line = assert(buflines.line(self.bufnr, lnum))
    jelly.debug("picked %s", line)

    close_current_win()
    self.on_pick(line)
  end

  function Impl:pick_first()
    local count = buflines.count(self.bufnr)
    if count == 1 then return jelly.debug("no match") end

    local line = assert(buflines.line(self.bufnr, 1))
    jelly.debug("picked %s", line)

    close_current_win()
    self.on_pick(line)
  end

  function Impl:cancel() close_current_win() end

  ---@param bufnr integer
  ---@param on_pick fun(line: string)
  ---@return beckon.RHS
  function RHS(bufnr, on_pick) return setmetatable({ bufnr = bufnr, on_pick = on_pick }, Impl) end
end

---@param candidates string[]
---@param on_pick fun(line: string)
return function(candidates, on_pick)
  local bufnr
  do
    bufnr = Ephemeral({ modifiable = true, handyclose = true })
    ---token*1
    buflines.append(bufnr, 0, "")
    ---matches*n
    buflines.replaces(bufnr, 1, 1, candidates)

    do
      local bm = bufmap.wraps(bufnr)
      local rhs = RHS(bufnr, on_pick)
      bm.i("<cr>", function() rhs:pick_first() end)
      bm.i("<space>", function() rhs:pick_first() end)
      bm.n("<cr>", function() rhs:pick_cursor() end)
      bm.i("<c-c>", function() rhs:cancel() end)
    end

    do
      local aug = augroups.BufAugroup(bufnr, true)

      local last_token = ""
      local function callback()
        local token = assert(buflines.line(bufnr, 0))
        if token == last_token then return end
        last_token = token

        buflines.replaces(bufnr, 1, buflines.count(bufnr), fuzzymatch(candidates, token))
      end

      aug:repeats("TextChangedI", { callback = callback })
      aug:repeats("TextChanged", { callback = callback })
    end
  end

  local winid = rifts.open.fragment(
    --
    bufnr,
    true,
    { relative = "editor", border = "single" },
    { width = 0.5, height = 0.8, vertical = "mid", horizontal = "mid", ns = facts.floatwin_ns }
  )
  prefer.wo(winid, "wrap", false)

  feedkeys("i", "n")
end
