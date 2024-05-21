local M = {}

local ctx = require("infra.ctx")
local ex = require("infra.ex")
local fn = require("infra.fn")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("beckon", "debug")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")
local winsplit = require("infra.winsplit")

local Beckon = require("beckon.Beckon")
local facts = require("beckon.facts")
local ropes = require("string.buffer")

local api = vim.api

local contracts = {}
do
  ---@param str string
  ---@param ... string|number @meta's
  ---@return string line @pattern='{str} ({meta,meta})'
  function contracts.format_line(str, ...)
    local rope = ropes.new()
    for i = 1, select("#", ...) do
      rope:putf(",%s", select(i, ...))
    end
    local meta = rope:skip(1):get()
    return string.format("%s (%s)", str, meta)
  end

  ---@param line string
  ---@return string str
  ---@return string|number ... meta
  function contracts.parse_line(line)
    local paren_at = strlib.rfind(line, "(")
    assert(paren_at, line)
    local str = string.sub(line, 1, paren_at - #" (")
    local right = string.sub(line, paren_at + #"(", #line - #")")
    return str, unpack(fn.split(right, ","))
  end
end

do
  local function is_normal_buf(bufnr)
    local name = api.nvim_buf_get_name(bufnr)
    if name == "" then return false end
    if strlib.find(name, "://") then return false end
    if prefer.bo(bufnr, "buftype") ~= "" then return false end
    return true
  end

  local acts = {}
  do
    acts.i = function(bufnr) api.nvim_win_set_buf(0, bufnr) end
    acts.o = function(bufnr) winsplit("below", bufnr) end
    acts.v = function(bufnr) winsplit("right", bufnr) end
    acts.t = function(bufnr) ex.eval("tab sbuffer %d", bufnr) end

    acts.cr = acts.i
    acts.space = acts.i
    acts.a = acts.i
  end

  local last_query

  function M.buffers()
    local candidates
    do
      local iter = fn.iter(api.nvim_list_bufs())
      local curbufnr = api.nvim_get_current_buf()
      iter = fn.filter(function(bufnr) return bufnr ~= curbufnr end, iter)
      iter = fn.filter(is_normal_buf, iter)
      iter = fn.map(function(bufnr)
        local name = fs.shorten(api.nvim_buf_get_name(bufnr))
        return contracts.format_line(name, bufnr)
      end, iter)
      candidates = fn.tolist(iter)
      if #candidates == 0 then return jelly.info("no other buffers") end
    end

    Beckon("buffers", candidates, last_query, function(query, action, line)
      last_query = query

      local _, bufnr = contracts.parse_line(line)
      bufnr = assert(tonumber(bufnr))

      assert(acts[action])(bufnr)
    end)
  end
end

do
  local acts = {}
  do
    acts.i = function(bufname) ex("buffer", bufname) end
    acts.o = function(bufname) winsplit("below", bufname) end
    acts.v = function(bufname) winsplit("right", bufname) end
    acts.t = function(bufname) ex("tabedit", bufname) end

    acts.cr = acts.i
    acts.space = acts.i
    acts.a = acts.i
  end

  local last_query

  function M.args()
    local candidates = {}
    do --no matter it's global or win-local
      local nargs = vim.fn.argc()
      if nargs == 0 then return jelly.info("empty arglist") end

      for i in fn.range(nargs) do
        table.insert(candidates, contracts.format_line(vim.fn.argv(i), i))
      end
    end

    Beckon("args", candidates, last_query, function(query, action, line)
      last_query = query

      local bufname = contracts.parse_line(line)
      assert(acts[action])(bufname)
    end)
  end
end

do
  local function load_digraphs()
    local path = fs.joinpath(facts.root, "data/digraphs")
    return fn.tolist(io.lines(path))
  end

  ---@type string[]|nil
  local candidates

  local last_query

  function M.digraphs()
    if candidates == nil then candidates = load_digraphs() end

    Beckon("digraphs", candidates, last_query, function(query, _, line)
      last_query = query

      local char = assert(fn.split_iter(line, " ")())
      api.nvim_put({ char }, "c", true, false)
    end)
  end
end

do
  local acts = {}
  do
    ---@param side infra.winsplit.Side
    ---@param src_winid integer
    ---@param src_bufnr integer
    local function main(side, src_winid, src_bufnr)
      local src_view
      local src_wo = {}
      ctx.win(src_winid, function() src_view = vim.fn.winsaveview() end)
      for _, opt in ipairs({ "list" }) do
        src_wo[opt] = prefer.wo(src_winid, opt)
      end

      --clone src win
      winsplit(side, src_bufnr)
      vim.fn.winrestview(src_view)
      local winid = api.nvim_get_current_win()
      for opt, val in pairs(src_wo) do
        prefer.wo(winid, opt, val)
      end
    end

    acts.i = function(winid, bufnr) main("right", winid, bufnr) end
    acts.o = function(winid, bufnr) main("below", winid, bufnr) end
    acts.v = function(winid, bufnr) main("right", winid, bufnr) end
    acts.t = function(_, _) return jelly.warn("unexpected action c-t against beckon.windows") end

    acts.cr = acts.i
    acts.space = acts.i
    acts.a = acts.i
  end

  local last_query

  function M.windows()
    local candidates = {}
    do
      local curtab = api.nvim_get_current_tabpage()
      local tab_iter = fn.filter(function(tabid) return tabid ~= curtab end, api.nvim_list_tabpages())

      for tabid in tab_iter do
        local tabnr = api.nvim_tabpage_get_number(tabid)
        for winid in fn.iter(api.nvim_tabpage_list_wins(tabid)) do
          local bufnr = api.nvim_win_get_buf(winid)
          local winnr = api.nvim_win_get_number(winid)
          local bufname = api.nvim_buf_get_name(bufnr)
          bufname = bufname == "" and "__" or fs.shorten(bufname)

          table.insert(candidates, contracts.format_line(string.format("%d.%d %s", tabnr, winnr, bufname), winid, bufnr))
        end
      end
    end

    Beckon("windows", candidates, last_query, function(query, action, line)
      last_query = query

      local _, winid, bufnr = contracts.parse_line(line)
      winid = assert(tonumber(winid))
      bufnr = assert(tonumber(bufnr))

      assert(acts[action])(winid, bufnr)
    end)
  end
end

return M
