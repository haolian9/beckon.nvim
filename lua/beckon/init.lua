local M = {}

local bufopen = require("infra.bufopen")
local ctx = require("infra.ctx")
local fs = require("infra.fs")
local itertools = require("infra.itertools")
local jelly = require("infra.jellyfish")("beckon", "debug")
local listlib = require("infra.listlib")
local prefer = require("infra.prefer")
local project = require("infra.project")
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
    return str, unpack(strlib.splits(right, ","))
  end
end

do
  ---@param bufnr integer
  ---@return true?
  local function is_searchable_buf(bufnr)
    --no matter if it's
    --* not listed: <c-o>/jumplist
    --* not loaded
    --* unnamed: enew, #1

    if prefer.bo(bufnr, "buftype") ~= "" then return end

    local bufname = api.nvim_buf_get_name(bufnr)
    if strlib.find(bufname, "://") then return end

    return true
  end

  ---@param root string
  ---@param bufnr integer
  ---@return string
  local function resolve_bufname(root, bufnr)
    local bufname = api.nvim_buf_get_name(bufnr)
    if bufname == "" then return "__" end
    local relative = fs.relative_path(root, bufname)
    return fs.shorten(relative or bufname)
  end

  local acts = {}
  do
    acts.i = bufopen.inplace
    acts.o = bufopen.below
    acts.v = bufopen.right
    acts.t = bufopen.tab

    acts.cr = bufopen.inplace
    acts.space = bufopen.inplace
    acts.a = bufopen.inplace
  end

  local last_query

  function M.buffers()
    local candidates
    do
      local bufnrs = api.nvim_list_bufs()
      if #bufnrs == 1 then return jelly.info("no other buffers") end

      local iter
      iter = itertools.iter(bufnrs)
      iter = itertools.filter(is_searchable_buf, iter)
      local root = project.working_root()
      iter = itertools.map(function(bufnr) return contracts.format_line(resolve_bufname(root, bufnr), bufnr) end, iter)

      --todo: sort by using frequency

      candidates = itertools.tolist(iter)
      if #candidates == 0 then return jelly.info("no other buffers") end
    end

    Beckon("buffers", candidates, function(query, action, line)
      last_query = query

      local _, bufnr = contracts.parse_line(line)
      bufnr = assert(tonumber(bufnr))

      assert(acts[action])(bufnr)
    end, { default_query = last_query, strict_path = true })
  end
end

do
  ---@param root string
  ---@param arg string
  ---@return string
  local function resolve_argname(root, arg) return fs.shorten(fs.relative_path(root, arg) or arg) or arg end

  local acts = {}
  do
    acts.i = bufopen.inplace
    acts.o = bufopen.below
    acts.v = bufopen.right
    acts.t = bufopen.tab

    acts.cr = bufopen.inplace
    acts.space = bufopen.inplace
    acts.a = bufopen.inplace
  end

  local last_query

  function M.args()
    local candidates = {}
    do --no matter it's global or win-local
      local args = vim.fn.argv(-1)
      assert(type(args) == "table")
      if #args == 0 then return jelly.info("empty arglist") end

      local iter
      iter = listlib.enumerate(args)
      local root = project.working_root()
      iter = itertools.mapn(function(i, arg) return contracts.format_line(resolve_argname(root, arg), i) end, iter)
      candidates = itertools.tolist(iter)
    end

    Beckon("args", candidates, function(query, action, line)
      last_query = query

      local _, i = contracts.parse_line(line)
      i = assert(tonumber(i))
      local arg = vim.fn.argv(i)

      assert(acts[action])(arg)
    end, { default_query = last_query })
  end
end

do
  local function load_digraphs()
    local path = fs.joinpath(facts.root, "data/digraphs")
    local list = itertools.tolist(io.lines(path))
    return setmetatable(list, { __mode = "v" })
  end

  ---@type string[]
  local candidates = {}

  local last_query

  function M.digraphs()
    if #candidates == 0 then candidates = load_digraphs() end

    Beckon("digraphs", candidates, function(query, _, line)
      last_query = query

      local char = assert(strlib.iter_splits(line, " ")())
      api.nvim_put({ char }, "c", true, false)
    end, { default_query = last_query })
  end
end

do
  ---the emojis data comes from: https://github.com/Allaman/emoji.nvim
  local function load_emojis()
    local path = fs.joinpath(facts.root, "data/emojis")
    local list = itertools.tolist(io.lines(path))
    return setmetatable(list, { __mode = "v" })
  end

  ---@type string[]
  local candidates = {}

  local last_query

  function M.emojis()
    if #candidates == 0 then candidates = load_emojis() end

    Beckon("emojis", candidates, function(query, _, line)
      last_query = query

      local char = assert(strlib.iter_splits(line, " ")())
      api.nvim_put({ char }, "c", true, false)
    end, { default_query = last_query })
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
      local tab_iter = itertools.filter(function(tabid) return tabid ~= curtab end, api.nvim_list_tabpages())

      for tabid in tab_iter do
        local tabnr = api.nvim_tabpage_get_number(tabid)
        for winid in itertools.iter(api.nvim_tabpage_list_wins(tabid)) do
          local bufnr = api.nvim_win_get_buf(winid)
          local winnr = api.nvim_win_get_number(winid)
          local bufname = api.nvim_buf_get_name(bufnr)
          bufname = bufname == "" and "__" or fs.shorten(bufname)

          table.insert(candidates, contracts.format_line(string.format("%d.%d %s", tabnr, winnr, bufname), winid, bufnr))
        end
      end
    end

    Beckon("windows", candidates, function(query, action, line)
      last_query = query

      local _, winid, bufnr = contracts.parse_line(line)
      winid = assert(tonumber(winid))
      bufnr = assert(tonumber(bufnr))

      assert(acts[action])(winid, bufnr)
    end, { default_query = last_query })
  end
end

do --the same as puff.select
  ---@param entries string[]
  ---@param opts {prompt: string?, format_item: fun(entry: string): (string), kind: string?}
  ---@param callback fun(entry: string?, index: number?)
  function M.select(entries, opts, callback)
    Beckon("select", entries, function(_, _, line)
      --
    end)
    --
  end
end

return M
