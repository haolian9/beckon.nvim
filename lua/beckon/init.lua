local M = {}

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
    acts.o = function(bufnr) winsplit("above", bufnr) end
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

    Beckon(candidates, last_query, function(query, action, line)
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

    Beckon(candidates, last_query, function(query, action, line)
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

    Beckon(candidates, last_query, function(query, _, line)
      last_query = query

      local char = assert(fn.split_iter(line, " ")())
      api.nvim_put({ char }, "c", true, false)
    end)
  end
end

return M
