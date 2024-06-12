---design ghoices
---* no large datasets, or use fond instead
---* no cache, or use fond instead
---* one buffer and one window
---* the first line is for user input
---* the rest lines are matched results
---* no i_c-n and i_c-p
---* no i_c-u and i_c-d
---* no fzf --nth
---* focus line: cycle in visible match lines, reset to 0 when matches updated

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
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local strlib = require("infra.strlib")
local wincursor = require("infra.wincursor")

local facts = require("beckon.facts")
local fuzzymatch = require("beckon.fuzzymatch")
local himatch = require("beckon.himatch")

local api = vim.api
local uv = vim.uv

---@alias beckon.Action 'cr'|'space'|'i'|'a'|'v'|'o'|'t'
---@alias beckon.OnPick fun(query: string, action: beckon.Action, choice: string)

local signals = {}
do
  local aug = augroups.Augroup("beckon")

  ---@param bufnr integer
  ---@param match_opts beckon.fuzzymatch.Opts
  ---@param matches string[]
  function signals.matches_updated(bufnr, match_opts, matches) aug:emit("User", { pattern = "beckon:matches_updated", data = { bufnr = bufnr, match_opts = match_opts, matches = matches } }) end
  ---@param callback fun(args: {data: {bufnr:integer, match_opts:beckon.fuzzymatch.Opts, matches:string[]}})
  function signals.on_matches_updated(callback) aug:repeats("User", { pattern = "beckon:matches_updated", callback = callback }) end

  ---@param bufnr integer
  ---@param focus integer
  function signals.focus_moved(bufnr, focus) aug:emit("User", { pattern = "beckon:focus_moved", data = { bufnr = bufnr, focus = focus } }) end
  ---@param callback fun(args: {data: {bufnr:integer, focus:integer}})
  function signals.on_focus_moved(callback) aug:repeats("User", { pattern = "beckon:focus_moved", callback = callback }) end
end

---@param bufnr integer
---@return string @always be lowercase
local function get_query(bufnr)
  local line = assert(buflines.line(bufnr, 0))
  return string.lower(line)
end

---@param bufnr integer
---@param all_candidates string[]
---@param strict_path boolean
---@return fun()
local function MatchesUpdator(bufnr, all_candidates, strict_path)
  local last_token = ""
  local last_matches = all_candidates
  local timer = iuv.new_timer()

  ---@type beckon.fuzzymatch.Opts
  local match_opts = { strict_path = strict_path }

  return function()
    local token = get_query(bufnr)
    if token == last_token then return end

    local candidates
    if strlib.startswith(token, last_token) then
      candidates = last_matches
    else
      --maybe: also optimize for <c-h>/<del>/<c-w>
      candidates = all_candidates
    end

    local updator = vim.schedule_wrap(function()
      local matches
      do
        local start_time = uv.hrtime()
        matches = fuzzymatch(candidates, token, match_opts)
        local elapsed_time = uv.hrtime() - start_time
        jelly.info("matching against %d items, elapsed %.3fms", #candidates, elapsed_time / 1000000)
      end

      last_token, last_matches = token, matches

      --maybe: WinScrolled to append rest matches
      buflines.replaces(bufnr, 1, -1, listlib.slice(matches, 1, vim.go.lines))

      signals.matches_updated(bufnr, match_opts, matches)
      signals.focus_moved(bufnr, 0)
    end)

    uv.timer_stop(timer)
    uv.timer_start(timer, facts.update_interval, 0, updator)
  end
end

local open_win
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
      row = math.max(win_row - 1, 0)
    else
      height = win_height - 2 -- borders
      row = 0
    end

    return { width = width, height = height, row = row, col = col }
  end

  ---@param purpose string
  ---@param bufnr integer
  ---@return integer winid
  function open_win(purpose, bufnr)
    local winopts = { relative = "win", border = "single", zindex = 250, title = string.format("beckon://%s", purpose), title_pos = "center" }
    local host_winid = api.nvim_get_current_win()
    dictlib.merge(winopts, resolve_geometry(host_winid))

    local winid = rifts.open.win(bufnr, true, winopts)

    api.nvim_win_set_hl_ns(winid, facts.floatwin_ns)
    prefer.wo(winid, "wrap", false)

    return winid
  end
end

local create_buf
do
  local RHS
  do
    ---@class beckon.RHS
    ---@field bufnr integer
    ---@field focus integer @0-based; impacted by query line, buf line count and win height
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
    function Impl:pick_focus(action)
      local line = buflines.line(self.bufnr, self.focus + 1)

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

    function Impl:insert_to_normal() feedkeys("<esc>j^", "n") end

    ---@param step integer
    function Impl:move_focus(step)
      local winid = api.nvim_get_current_win()
      local win_height = api.nvim_win_get_height(winid)

      local high
      do
        local line_count = buflines.count(self.bufnr)
        high = win_height
        if line_count < win_height then high = line_count end
        high = high - 1 -- query line
        high = high - 1 -- count -> high
      end

      local focus = self.focus + step
      if focus < 0 then -- -1=high
        focus = high - ((-focus % (high + 1)) - 1)
      elseif focus > high then
        focus = focus % (high + 1)
      end

      self.focus = focus
      signals.focus_moved(self.bufnr, focus)
    end

    ---@param bufnr integer
    ---@param on_pick beckon.OnPick
    ---@return beckon.RHS
    function RHS(bufnr, on_pick) return setmetatable({ bufnr = bufnr, focus = 0, on_pick = on_pick }, Impl) end
  end

  ---@param purpose string @used for bufname, win title
  ---@param candidates string[]
  ---@param on_pick beckon.OnPick
  ---@param opts beckon.BeckonOpts
  function create_buf(purpose, candidates, on_pick, opts)
    local bufnr = Ephemeral({ modifiable = true, handyclose = true, namepat = string.format("beckon://%s/{bufnr}", purpose) })

    do
      ---@type beckon.fuzzymatch.Opts
      local match_opts = { strict_path = opts.strict_path }

      local query, matches
      if opts.default_query ~= nil then
        query = assert(opts.default_query)
        matches = fuzzymatch(candidates, query, match_opts)
      else
        query = ""
        matches = candidates
      end

      buflines.replace(bufnr, 0, query)
      buflines.replaces(bufnr, 1, -1, listlib.slice(matches, 1, vim.go.lines))

      signals.matches_updated(bufnr, match_opts, matches)
      signals.focus_moved(bufnr, 0)
    end

    do
      local aug = augroups.BufAugroup(bufnr, true)
      aug:repeats({ "TextChangedI", "TextChanged" }, { callback = MatchesUpdator(bufnr, candidates, opts.strict_path) })
    end

    do
      local bm = bufmap.wraps(bufnr)
      local rhs = RHS(bufnr, on_pick)

      bm.n("gi", function() rhs:goto_query_line() end)

      bm.i("<cr>", function() rhs:pick_focus("cr") end)
      bm.i("<space>", function() rhs:pick_focus("space") end)
      bm.i("<c-m>", function() rhs:pick_focus("cr") end)
      bm.i("<c-/>", function() rhs:pick_focus("v") end)
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

      bm.i("<c-n>", function() rhs:move_focus(1) end)
      bm.i("<c-p>", function() rhs:move_focus(-1) end)

      ---to keep consistent experience with fond
      bm.i("<esc>", function() rhs:cancel() end)
      bm.i("<c-[>", function() rhs:cancel() end)
      bm.i("<c-]>", function() rhs:insert_to_normal() end)
    end

    return bufnr
  end
end

do --signal actions
  ---for each buffer
  ---@type {[integer]: integer}
  local query_xmarks = {}

  ---@param bufnr integer
  ---@param matches string[]
  local function update_query_xmarks(bufnr, matches)
    if query_xmarks[bufnr] ~= nil then api.nvim_buf_del_extmark(bufnr, facts.xm_query_ns, query_xmarks[bufnr]) end
    query_xmarks[bufnr] = api.nvim_buf_set_extmark(bufnr, facts.xm_query_ns, 0, 0, {
      virt_text_pos = "eol",
      virt_text = { { string.format("#%d", #matches), "Comment" } },
    })
  end

  ---@param bufnr integer
  ---@param match_opts beckon.fuzzymatch.Opts
  ---@param matches string[]
  local function update_token_highlights(bufnr, match_opts, matches)
    api.nvim_buf_clear_namespace(bufnr, facts.xm_hi_ns, 0, -1)

    local token = get_query(bufnr)
    if token == "" then return end

    ---currently it only processes the first page of the buffer,
    ---so there is no to use nvim_set_decoration_provider here
    local his = himatch(itertools.head(matches, api.nvim_win_get_height(0)), token, { strict_path = match_opts.strict_path })

    for index, ranges in itertools.enumerate(his) do
      local lnum = index + 1 --query line
      for _, range in ipairs(ranges) do
        api.nvim_buf_add_highlight(bufnr, facts.xm_hi_ns, "BeckonToken", lnum, range[1], range[2] + 1)
      end
    end
  end

  signals.on_matches_updated(function(args)
    local bufnr = args.data.bufnr
    if not api.nvim_buf_is_valid(bufnr) then return end

    local matches, match_opts = args.data.matches, args.data.match_opts

    update_query_xmarks(bufnr, matches)
    update_token_highlights(bufnr, match_opts, matches)
  end)

  signals.on_focus_moved(function(args)
    local bufnr = args.data.bufnr

    api.nvim_buf_clear_namespace(bufnr, facts.xm_focus_ns, 0, -1)

    local lnum = args.data.focus + 1
    api.nvim_buf_add_highlight(bufnr, facts.xm_focus_ns, "BeckonFocusLine", lnum, 0, -1)
  end)
end

do --main
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

  ---@alias beckon.OpenWin fun(purpose: string, bufnr: integer):winid:integer

  ---@class beckon.BeckonOpts
  ---@field default_query? string
  ---@field strict_path? boolean @nil=false
  ---@field open_win? beckon.OpenWin

  ---@param purpose string @used for bufname, win title
  ---@param candidates string[]
  ---@param on_pick beckon.OnPick
  ---@param opts? beckon.BeckonOpts
  ---@return integer winid
  ---@return integer bufnr
  return function(purpose, candidates, on_pick, opts)
    opts = opts or {}
    if opts.strict_path == nil then opts.strict_path = false end
    if opts.open_win == nil then opts.open_win = open_win end

    local bufnr = create_buf(purpose, candidates, on_pick, opts)
    local winid = opts.open_win(purpose, bufnr)

    feedkeys("ggA", "n")

    if opts.default_query ~= nil and opts.default_query ~= "" then
      on_first_key(function(key)
        local code = string.byte(key)
        if code >= ascii.exclam and code <= ascii.tilde then --clear default query
          api.nvim_buf_set_text(bufnr, 0, 0, 0, #opts.default_query, { "" })
        end
      end)
    end

    return winid, bufnr
  end
end
