local ascii = require("infra.ascii")
local augroups = require("infra.augroups")
local buflines = require("infra.buflines")
local dictlib = require("infra.dictlib")
local Ephemeral = require("infra.Ephemeral")
local feedkeys = require("infra.feedkeys")
local itertools = require("infra.itertools")
local iuv = require("infra.iuv")
local jelly = require("infra.jellyfish")("beckon", "debug")
local bufmap = require("infra.keymap.buffer")
local listlib = require("infra.listlib")
local mi = require("infra.mi")
local ni = require("infra.ni")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local strlib = require("infra.strlib")
local wincursor = require("infra.wincursor")

local facts = require("beckon.facts")
local fuzzymatch = require("beckon.fuzzymatch")
local himatch = require("beckon.himatch")

local uv = vim.uv

local Context
do
  ---@class beckon.InvertBeckon.Context
  ---
  ---@field winid integer
  ---@field bufnr integer
  ---@field match_opts beckon.fuzzymatch.Opts
  ---@field all_candidates string[]
  ---@field focus integer @0-based; impacted by query line, buf line count and win height
  ---
  ---@field short integer

  ---@param winid integer
  ---@param bufnr integer
  ---@param match_opts beckon.fuzzymatch.Opts
  ---@return beckon.InvertBeckon.Context
  function Context(winid, bufnr, match_opts, all_candidates) return { winid = winid, bufnr = bufnr, match_opts = match_opts, all_candidates = all_candidates, focus = 0, short = 0 } end
end

local signals = {}
do
  local aug = augroups.Augroup("beckon://invert")

  ---@param ctx beckon.InvertBeckon.Context
  ---@param matches string[]
  function signals.matches_updated(ctx, matches) aug:emit("User", { pattern = "beckon:invert:matches_updated", data = { ctx = ctx, matches = matches } }) end
  ---@param callback fun(args: {data: {ctx:beckon.InvertBeckon.Context, matches:string[]}})
  function signals.on_matches_updated(callback) aug:repeats("User", { pattern = "beckon:invert:matches_updated", callback = callback }) end

  ---@param ctx beckon.InvertBeckon.Context
  function signals.focus_moved(ctx) aug:emit("User", { pattern = "beckon:invert:focus_moved", data = { ctx = ctx } }) end
  ---@param callback fun(args: {data: {ctx:beckon.InvertBeckon.Context}})
  function signals.on_focus_moved(callback) aug:repeats("User", { pattern = "beckon:invert:focus_moved", callback = callback }) end
end

local contracts = {}
do
  ---@param bufnr integer
  ---@return string @always be lowercase
  function contracts.query(bufnr)
    local line = assert(buflines.line(bufnr, -1))
    return string.lower(line)
  end

  function contracts.query_lnum(bufnr) return buflines.high(bufnr) end

  function contracts.focus_to_lnum(bufnr, focus)
    local high = buflines.high(bufnr)
    return high - focus - 1 --query line
  end

  ---@param ctx beckon.InvertBeckon.Context
  ---@param step integer @accepts negative
  ---@return integer?
  function contracts.focus_jump_target(ctx, step)
    local high
    do
      local win_height = ni.win_get_height(ctx.winid)
      local line_count = buflines.count(ctx.bufnr)
      if line_count < win_height then
        high = line_count
      else
        high = win_height
      end
      high = high - 1 -- query line
      high = high - ctx.short -- blank lines
      high = high - 1 -- count -> high
      if high < 1 then return end
    end

    local dest = ctx.focus + step

    if dest < 0 then -- -1=high
      return high - ((-dest % (high + 1)) - 1)
    elseif dest > high then
      return dest % (high + 1)
    else
      return dest
    end
  end
end

local MatchesUpdator
do
  ---@class beckon.InvertBeckon.MatchesUpdator
  ---@field private ctx          beckon.InvertBeckon.Context
  ---@field private ready        boolean @whether ready for update
  ---@field private last_token   string
  ---@field private last_matches string[]
  ---@field private timer        uv_timer_t
  local Impl = {}
  Impl.__index = Impl

  function Impl:ready_for_update() self.ready = true end

  ---@private
  ---@param token string
  ---@param candidates string[]
  function Impl:update(token, candidates)
    local ctx = self.ctx

    local matches
    do
      local start_time = uv.hrtime()
      matches = fuzzymatch(candidates, token, ctx.match_opts)
      local elapsed_time = uv.hrtime() - start_time
      jelly.info("matches %d in %.3fms", #candidates, elapsed_time / 1000000)
    end

    self.last_token, self.last_matches = token, matches

    local body = listlib.head(matches, 150)
    buflines.replaces(ctx.bufnr, 0, -2, body)

    local win_height = ni.win_get_height(ctx.winid)

    do --filling blank lines
      ctx.short = math.max(win_height - #body - 1, 0) --query line
      if ctx.short > 0 then buflines.prepends(ctx.bufnr, 0, listlib.zeros(ctx.short, "")) end
    end

    --keep last line at the bottom of the window
    wincursor.follow(ctx.winid, "stay")

    ctx.focus = 0

    signals.matches_updated(ctx, matches)
    signals.focus_moved(ctx)
  end

  function Impl:on_update()
    if not self.ready then return jelly.debug("updator is not ready for update") end

    local ctx = self.ctx

    local token = contracts.query(ctx.bufnr)
    if token == self.last_token then return end

    local candidates
    if strlib.startswith(token, self.last_token) then
      candidates = self.last_matches
    else
      --maybe: also optimize for <c-h>/<del>/<c-w>
      candidates = ctx.all_candidates
    end

    local updator = vim.schedule_wrap(function() self:update(token, candidates) end)
    self.timer:stop()
    self.timer:start(facts.update_interval, 0, updator)
  end

  ---@param ctx beckon.InvertBeckon.Context
  ---@return beckon.InvertBeckon.MatchesUpdator
  function MatchesUpdator(ctx)
    return setmetatable({
      ctx = ctx,
      ready = false,
      last_token = "",
      last_matches = ctx.all_candidates,
      timer = iuv.new_timer(),
    }, Impl)
  end
end

local default_open_win
do
  ---@param host_winid integer
  local function resolve_geometry(host_winid)
    local winfo = assert(vim.fn.getwininfo(host_winid)[1])
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

  ---@param purpose string
  ---@param bufnr integer
  ---@return integer winid
  function default_open_win(purpose, bufnr)
    local winopts = { relative = "win", border = "single", zindex = 250, footer = string.format("beckon://%s", purpose), footer_pos = "center" }
    local host_winid = ni.get_current_win()
    dictlib.merge(winopts, resolve_geometry(host_winid))

    local winid = rifts.open.win(bufnr, true, winopts)

    ni.win_set_hl_ns(winid, facts.floatwin_ns)

    return winid
  end
end

local buf_bind_rhs
do
  ---@class beckon.InvertBeckon.RHS
  ---@field ctx beckon.InvertBeckon.Context
  ---@field on_pick beckon.OnPick
  local RHS = {}
  RHS.__index = RHS

  local function close_current_win()
    if ni.get_mode().mode == "i" then feedkeys("<esc>", "n") end
    ni.win_close(0, false)
  end

  function RHS:goto_query_line() feedkeys("GA", "n") end

  ---@param action beckon.Action
  ---@return boolean? picked @nil=false
  function RHS:pick_cursor(action)
    local ctx = self.ctx

    local lnum = wincursor.lnum()
    if ctx.short > 0 and lnum <= ctx.short then return jelly.info("not a match; filling blank line") end
    if lnum == contracts.query_lnum(ctx.bufnr) then return jelly.info("not a match; query line") end

    local line = assert(buflines.line(ctx.bufnr, lnum))
    local query = contracts.query(ctx.bufnr)

    close_current_win()

    ---to avoid possible E1159
    vim.schedule(function() self.on_pick(query, action, line) end)

    return true
  end

  ---@param action_or_key 'i'|'a'|'v'|'o'|'t'
  function RHS:pick_cursor_or_passthrough(action_or_key)
    if self:pick_cursor(action_or_key) then return end
    feedkeys.keys(action_or_key, "n")
  end

  ---@param action beckon.Action
  function RHS:pick_focus(action)
    local ctx = self.ctx

    local line = buflines.line(ctx.bufnr, contracts.focus_to_lnum(ctx.bufnr, ctx.focus))

    if line == nil then
      close_current_win()
      return jelly.info("no match")
    end

    local query = contracts.query(ctx.bufnr)
    close_current_win()

    ---to avoid possible E1159
    vim.schedule(function() self.on_pick(query, action, line) end)
  end

  function RHS:cancel() close_current_win() end

  function RHS:insert_to_normal() feedkeys("<esc>k^", "n") end

  ---@param step integer
  function RHS:move_focus(step)
    local ctx = self.ctx
    local dest = contracts.focus_jump_target(ctx, step)
    ctx.focus = dest or 0
    if dest == nil then return jelly.warn("no matches to focus") end
    signals.focus_moved(ctx)
  end

  ---@param ctx beckon.InvertBeckon.Context
  ---@param on_pick beckon.OnPick
  function buf_bind_rhs(ctx, on_pick)
    local bm = bufmap.wraps(ctx.bufnr)
    local rhs = setmetatable({ ctx = ctx, on_pick = on_pick }, RHS)

    bm.n("gi", function() rhs:goto_query_line() end)

    bm.i("<cr>", function() rhs:pick_focus("cr") end)
    bm.i("<space>", function() rhs:pick_focus("space") end)
    bm.i("<c-m>", function() rhs:pick_focus("cr") end)
    bm.i("<c-/>", function() rhs:pick_focus("v") end)
    bm.i("<c-_>", function() rhs:pick_focus("v") end)
    bm.i("<c-i>", function() rhs:pick_focus("i") end)
    ---no mapping <c-a> here, as i mapped it to <home>
    bm.i("<c-v>", function() rhs:pick_focus("v") end)
    bm.i("<c-o>", function() rhs:pick_focus("o") end)
    bm.i("<c-t>", function() rhs:pick_focus("t") end)

    bm.n("<cr>", function() rhs:pick_cursor("cr") end)
    bm.n("gf", function() rhs:pick_cursor("cr") end)
    bm.n("i", function() rhs:pick_cursor_or_passthrough("i") end)
    bm.n("a", function() rhs:pick_cursor_or_passthrough("a") end)
    bm.n("v", function() rhs:pick_cursor_or_passthrough("v") end)
    bm.n("o", function() rhs:pick_cursor_or_passthrough("o") end)
    bm.n("t", function() rhs:pick_cursor_or_passthrough("t") end)

    bm.i("<c-c>", function() rhs:cancel() end)
    bm.i("<c-d>", function() rhs:cancel() end)

    bm.i("<c-n>", function() rhs:move_focus(-1) end)
    bm.i("<c-p>", function() rhs:move_focus(1) end)
    bm.i("<c-j>", function() rhs:move_focus(-1) end)
    bm.i("<c-k>", function() rhs:move_focus(1) end)

    ---to keep consistent experience with fond
    bm.i("<esc>", function() rhs:cancel() end)
    bm.i("<c-[>", function() rhs:cancel() end)
    bm.i("<c-]>", function() rhs:insert_to_normal() end)
  end
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

do --signal actions
  ---for each buffer
  ---@type {[integer]: integer}
  local query_xmarks = {}

  ---@param bufnr integer
  ---@param matches string[]
  local function upsert_query_xmarks(bufnr, matches)
    local lnum = contracts.query_lnum(bufnr)
    query_xmarks[bufnr] = ni.buf_set_extmark(bufnr, facts.xm_query_ns, lnum, 0, {
      id = query_xmarks[bufnr],
      virt_text_pos = "eol",
      virt_text = { { string.format("#%d", #matches), "Comment" } },
    })
  end

  ---@param ctx beckon.InvertBeckon.Context
  ---@param matches string[]
  local function update_token_highlights(ctx, matches)
    ni.buf_clear_namespace(ctx.bufnr, facts.xm_hi_ns, 0, -1)

    if #matches == 0 then return end

    local token = contracts.query(ctx.bufnr)
    if token == "" then return end

    ---currently it only processes the first page of the buffer,
    ---so there is need no to use nvim_set_decoration_provider here

    local start_lnum, stop_lnum
    do
      local height = ni.win_get_height(ctx.winid)
      local high = buflines.high(ctx.bufnr)
      if ctx.short > 0 then
        start_lnum = high - (height - ctx.short)
      else
        start_lnum = high - height
      end
      start_lnum = start_lnum + 1 --query line
      stop_lnum = high --exclusive
    end

    local lines = buflines.lines(ctx.bufnr, start_lnum, stop_lnum)
    local his = himatch(lines, token, { strict_path = ctx.match_opts.strict_path })

    for i, ranges in itertools.enumerate(his) do
      local lnum = i + start_lnum
      for _, range in ipairs(ranges) do
        ni.buf_set_extmark(ctx.bufnr, facts.xm_hi_ns, lnum, range[1], {
          end_row = lnum,
          end_col = range[2] + 1,
          hl_group = "BeckonToken",
          hl_mode = "combine",
        })
      end
    end
  end

  signals.on_matches_updated(function(args)
    local ctx, matches = args.data.ctx, args.data.matches
    if not ni.buf_is_valid(ctx.bufnr) then return end

    upsert_query_xmarks(ctx.bufnr, matches)
    update_token_highlights(ctx, matches)
  end)

  signals.on_focus_moved(function(args)
    local ctx = args.data.ctx

    ni.buf_clear_namespace(ctx.bufnr, facts.xm_focus_ns, 0, -1)
    local lnum = contracts.focus_to_lnum(ctx.bufnr, ctx.focus)
    if lnum > buflines.count(ctx.bufnr) - 1 then return end
    mi.buf_highlight_line(ctx.bufnr, facts.xm_focus_ns, lnum, "BeckonFocusLine")
  end)
end

---@param purpose string @used for bufname, win title
---@param candidates string[]
---@param on_pick beckon.OnPick
---@param opts? beckon.BeckonOpts
---@return integer winid
---@return integer bufnr
return function(purpose, candidates, on_pick, opts)
  opts = opts or {}
  if opts.strict_path == nil then opts.strict_path = false end

  local bufnr = Ephemeral({ modifiable = true, handyclose = true, namepat = string.format("beckon://%s/{bufnr}", purpose) })
  local winid = (opts.open_win or default_open_win)(purpose, bufnr)
  local ctx = Context(winid, bufnr, { strict_path = opts.strict_path, sort = "desc" }, candidates)

  do --mandatory winopts
    local wo = prefer.win(winid)
    wo.wrap = false
    wo.signcolumn = "yes:1"
  end

  buf_bind_rhs(ctx, on_pick)

  local updator = MatchesUpdator(ctx)

  do --match-body, query-foot
    local query = opts.default_query or ""
    ---@diagnostic disable-next-line: invisible
    updator:update(query, candidates)
    buflines.replace(bufnr, -1, query)
  end

  local aug = augroups.BufAugroup(bufnr, "beckon", true)
  aug:repeats({ "TextChangedI", "TextChanged", "WinResized" }, { callback = function() updator:on_update() end })

  feedkeys("GA", "n")

  if opts.default_query ~= nil and opts.default_query ~= "" then
    on_first_key(function(key)
      local code = string.byte(key)
      if code >= ascii.exclam and code <= ascii.tilde then --clear default query
        ni.buf_set_text(bufnr, -1, 0, -1, #opts.default_query, { "" })
      end
    end)
  end

  updator:ready_for_update()

  return winid, bufnr
end
