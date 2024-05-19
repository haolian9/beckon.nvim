local M = {}

local ex = require("infra.ex")
local fn = require("infra.fn")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("beckon", "debug")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")

local facts = require("beckon.facts")
local ui = require("beckon.ui")

local api = vim.api

do
  local function is_normal_buf(bufnr)
    local name = api.nvim_buf_get_name(bufnr)
    if name == "" then return false end
    if strlib.find(name, "://") then return false end
    if prefer.bo(bufnr, "buftype") ~= "" then return false end
    return true
  end

  ---@param bufnr integer
  ---@return string
  local function format_line(bufnr)
    local bufname = api.nvim_buf_get_name(bufnr)
    local name = fs.shorten(bufname)
    return string.format("%d %s", bufnr, name)
  end

  ---@param line string
  ---@return integer
  local function extract_bufnr(line)
    local bufnr
    bufnr = assert(select(1, string.match(line, "^(%d+) ")), line)
    bufnr = assert(tonumber(bufnr), bufnr)
    return bufnr
  end

  local last_query

  function M.buffers()
    local candidates
    do
      local iter = fn.iter(api.nvim_list_bufs())
      local curbufnr = api.nvim_get_current_buf()
      iter = fn.filter(function(bufnr) return bufnr ~= curbufnr end, iter)
      iter = fn.filter(is_normal_buf, iter)
      iter = fn.map(format_line, iter)
      candidates = fn.tolist(iter)
      if #candidates == 0 then return jelly.info("no other buffers") end
    end

    ui(candidates, last_query, function(query, action, line)
      last_query = query

      local bufnr = extract_bufnr(line)
      ---todo: honor the action
      local _ = action
      api.nvim_win_set_buf(0, bufnr)
    end)
  end
end

do
  local last_query

  function M.args()
    local candidates = {}
    do --no matter it's global or win-local
      for i = 0, vim.fn.argc() - 1 do
        table.insert(candidates, string.format("%d %s", i, vim.fn.argv(i)))
      end
      if #candidates == 0 then return jelly.info("empty arglist") end
    end

    ui(candidates, last_query, function(query, action, line)
      last_query = query

      local arg = assert(select(1, string.match(line, "^%d+ (.+)$")))
      ---todo: honor the action
      local _ = action
      ex.cmd("edit", arg)
    end)
  end
end

do
  local function load_digraphs()
    local path = fs.joinpath(facts.root, "lua/beckon/digraphs")
    jelly.debug("digraphs path: %s", path)
    return fn.tolist(io.lines(path))
  end

  ---@type string[]|nil
  local candidates

  local last_query

  function M.digraphs()
    if candidates == nil then candidates = load_digraphs() end

    ui(candidates, last_query, function(query, _, line)
      last_query = query

      local char = assert(fn.split_iter(line, " ")())
      api.nvim_put({ char }, "c", true, false)
    end)
  end
end

return M
