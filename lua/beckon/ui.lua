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
local uv = vim.loop

---@alias beckon.Action 'cr'|'space'|'v'|'o'|'t'
---@alias beckon.OnPick fun(query: string, action: beckon.Action, choice: string)

---@param bufnr integer
---@return string @always be lowercase
local function get_query(bufnr)
  local line = assert(buflines.line(bufnr, 0))
  return string.lower(line)
end

local RHS
do
  ---@class beckon.RHS
  ---@field bufnr integer
  ---@field on_pick beckon.OnPick
  local Impl = {}
  Impl.__index = Impl

  local function close_current_win()
    if api.nvim_get_mode().mode == "i" then feedkeys("<esc>", "n") end
    api.nvim_win_close(0, false)
  end

  function Impl:goto_query_line() feedkeys("ggA", "n") end

  ---@param action beckon.Action
  function Impl:pick_cursor(action)
    local count = buflines.count(self.bufnr)
    if count == 1 then return jelly.debug("no match") end

    local lnum = wincursor.lnum()
    if lnum == 0 then return jelly.debug("not a match") end

    local line = assert(buflines.line(self.bufnr, lnum))
    jelly.debug("picked %s", line)

    local query = get_query(self.bufnr)
    close_current_win()

    vim.schedule(function() ---to avoid possible E1159
      self.on_pick(query, action, line)
    end)
  end

  ---@param action beckon.Action
  function Impl:pick_first(action)
    local count = buflines.count(self.bufnr)
    if count == 1 then return jelly.debug("no match") end

    local line = assert(buflines.line(self.bufnr, 1))
    jelly.debug("picked %s", line)

    local query = get_query(self.bufnr)
    close_current_win()

    vim.schedule(function() ---to avoid possible E1159
      self.on_pick(query, action, line)
    end)
  end

  function Impl:cancel() close_current_win() end

  ---@param bufnr integer
  ---@param on_pick beckon.OnPick
  ---@return beckon.RHS
  function RHS(bufnr, on_pick) return setmetatable({ bufnr = bufnr, on_pick = on_pick }, Impl) end
end

---@param bufnr integer
---@param candidates string[]
---@return fun()
local function MatchesUpdator(bufnr, candidates)
  local last_token = ""
  local timer = uv.new_timer()

  return function()
    local token = get_query(bufnr)
    if token == last_token then return end
    last_token = token

    local updator = vim.schedule_wrap(function() buflines.replaces(bufnr, 1, buflines.count(bufnr), fuzzymatch(candidates, token)) end)

    uv.timer_stop(timer)
    uv.timer_start(timer, facts.update_interval, 0, updator)
  end
end

---@param candidates string[]
---@param default_query? string
---@param on_pick beckon.OnPick
return function(candidates, default_query, on_pick)
  local bufnr
  do
    bufnr = Ephemeral({ modifiable = true, handyclose = true })

    if default_query == nil then
      buflines.replace(bufnr, 0, "")
      buflines.replaces(bufnr, 1, 1, candidates)
    else
      buflines.replace(bufnr, 0, default_query)
      buflines.replaces(bufnr, 1, 1, fuzzymatch(candidates, default_query))
    end

    do
      local bm = bufmap.wraps(bufnr)
      local rhs = RHS(bufnr, on_pick)

      bm.n("gi", function() rhs:goto_query_line() end)

      bm.i("<cr>", function() rhs:pick_first("cr") end)
      bm.i("<space>", function() rhs:pick_first("space") end)
      bm.i("<c-m>", function() rhs:pick_first("cr") end)
      bm.i("<c-/>", function() rhs:pick_first("v") end)
      bm.i("<c-o>", function() rhs:pick_first("o") end)
      bm.i("<c-t>", function() rhs:pick_first("t") end)

      bm.n("<cr>", function() rhs:pick_cursor("cr") end)
      bm.n("gf", function() rhs:pick_cursor("cr") end)
      bm.n("i", function() rhs:pick_cursor("cr") end)
      bm.n("v", function() rhs:pick_cursor("v") end)
      bm.n("o", function() rhs:pick_cursor("o") end)
      bm.n("t", function() rhs:pick_cursor("t") end)

      bm.n("<c-g>", function() error("not implemented") end)

      bm.i("<c-c>", function() rhs:cancel() end)
      bm.i("<c-d>", function() rhs:cancel() end)
    end

    do
      local aug = augroups.BufAugroup(bufnr, true)
      local update_matches = MatchesUpdator(bufnr, candidates)

      aug:repeats("TextChangedI", { callback = update_matches })
      aug:repeats("TextChanged", { callback = update_matches })
    end

    api.nvim_buf_set_extmark(bufnr, facts.querysuffix_ns, 0, 0, {
      virt_text_pos = "eol",
      virt_text = { { "<", "Search" } },
    })
  end

  local winid = rifts.open.fragment(
    --
    bufnr,
    true,
    { relative = "editor", border = "single" },
    { width = 0.5, height = 0.8, vertical = "mid", horizontal = "mid", ns = facts.floatwin_ns }
  )
  prefer.wo(winid, "wrap", false)

  feedkeys("ggA", "n")
end
