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
local dictlib = require("infra.dictlib")
local Ephemeral = require("infra.Ephemeral")
local feedkeys = require("infra.feedkeys")
local jelly = require("infra.jellyfish")("beckon", "debug")
local bufmap = require("infra.keymap.buffer")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local strlib = require("infra.strlib")
local wincursor = require("infra.wincursor")

local facts = require("beckon.facts")
local fuzzymatch = require("beckon.fuzzymatch")

local api = vim.api
local uv = vim.loop

---@alias beckon.Action 'cr'|'space'|'i'|'a'|'v'|'o'|'t'
---@alias beckon.OnPick fun(query: string, action: beckon.Action, choice: string)

--stolen from fond.fzf
--show prompt at cursor line when possible horizental center
local function resolve_geometry()
  local winid = api.nvim_get_current_win()

  local winfo = assert(vim.fn.getwininfo(winid)[1])
  local win_width, win_height = winfo.width, winfo.height
  -- takes folding into account
  local win_row = vim.fn.winline()

  --below magic numbers are based on
  --* urxvt, width=136, height=30
  --* st, width=174, height=39

  local width, col
  if win_width > 70 then
    width = math.floor(win_width * 0.6)
    col = math.floor(win_width * 0.2)
  elseif win_width > 45 then
    width = math.floor(win_width * 0.75)
    col = math.floor(win_width * 0.125)
  else
    width = win_width - 2 -- borders
    col = 0
  end

  local height, row
  if win_height > 15 then
    height = math.floor(win_height * 0.45)
    row = math.max(win_row - height - 1, 0)
  else
    height = win_height - 2 -- borders
    row = 0
  end

  return { width = width, height = height, row = row, col = col }
end

---@param bufnr integer
---@return string @always be lowercase
local function get_query(bufnr)
  local line = assert(buflines.line(bufnr, 0))
  return string.lower(line)
end

---@param callback fun(key: string)
local function on_first_key(callback)
  vim.schedule(function() --to ensure no more inputs
    vim.on_key(function(key)
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.on_key(nil, facts.onkey_ns)
      callback(key)
    end, facts.onkey_ns)
  end)
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
  ---@return boolean? picked @nil=false
  function Impl:pick_cursor(action)
    local lnum = wincursor.lnum()
    if lnum == 0 then return jelly.info("not a match") end

    local line = assert(buflines.line(self.bufnr, lnum))

    local query = get_query(self.bufnr)
    close_current_win()

    vim.schedule(function() ---to avoid possible E1159
      self.on_pick(query, action, line)
    end)

    return true
  end

  ---@param action_or_key 'i'|'a'|'v'|'o'|'t'
  function Impl:pick_cursor_or_passthrough(action_or_key)
    if self:pick_cursor(action_or_key) then return end
    feedkeys.keys(action_or_key, "n")
  end

  ---@param action beckon.Action
  function Impl:pick_first(action)
    local line = buflines.line(self.bufnr, 1)
    if line == nil then
      close_current_win()
      return jelly.info("no match")
    end

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
---@param complete_candidates string[]
---@return fun()
local function MatchesUpdator(bufnr, complete_candidates)
  local last_token = ""
  local last_matches = complete_candidates
  local timer = uv.new_timer()

  return function()
    local token = get_query(bufnr)
    if token == last_token then return end

    local candidates
    if strlib.startswith(token, last_token) then
      candidates = last_matches
    else
      --todo: also optimize for <c-h>/<del>/<c-w>
      candidates = complete_candidates
    end

    local updator = vim.schedule_wrap(function()
      local matches
      do
        local start_time = uv.hrtime()
        matches = fuzzymatch(candidates, token)
        local elapsed_time = uv.hrtime() - start_time
        jelly.info("matching against %d items, elapsed %.3fms", #candidates, elapsed_time / 1000000)
      end
      last_token, last_matches = token, matches
      buflines.replaces(bufnr, 1, buflines.count(bufnr), matches)
    end)

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
      bm.n("i", function() rhs:pick_cursor_or_passthrough("i") end)
      bm.n("a", function() rhs:pick_cursor_or_passthrough("a") end)
      bm.n("v", function() rhs:pick_cursor_or_passthrough("v") end)
      bm.n("o", function() rhs:pick_cursor_or_passthrough("o") end)
      bm.n("t", function() rhs:pick_cursor_or_passthrough("t") end)

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

  local winid
  do
    local winopts = dictlib.merged({ relative = "win", border = "single", zindex = 250 }, resolve_geometry())
    winid = rifts.open.win(bufnr, true, winopts)

    api.nvim_win_set_hl_ns(winid, facts.floatwin_ns)
    prefer.wo(winid, "wrap", false)
  end

  feedkeys("ggA", "n")

  if default_query ~= nil and default_query ~= "" then
    on_first_key(function(key)
      local code = string.byte(key)
      if code >= 0x21 and code <= 0x7e then --clear default query
        api.nvim_buf_set_text(bufnr, 0, 0, 0, #default_query, { "" })
      end
    end)
  end
end