local M = {}

local ex = require("infra.ex")
local fn = require("infra.fn")
local jelly = require("infra.jellyfish")("beckon", "debug")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")

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

  function M.buffers()
    local candidates
    do
      local iter = fn.iter(api.nvim_list_bufs())
      iter = fn.filter(is_normal_buf, iter)
      iter = fn.map(function(bufnr) return string.format("#%d %s", bufnr, api.nvim_buf_get_name(bufnr)) end, iter)
      candidates = fn.tolist(iter)
      if #candidates == 1 then return jelly.info("no other buffers") end
    end

    ui(candidates, function(line)
      local bufnr
      bufnr = assert(select(1, string.match(line, "^#(%d+) ")), line)
      bufnr = assert(tonumber(bufnr))

      api.nvim_win_set_buf(0, bufnr)
    end)
  end
end

function M.args()
  local candidates = {}
  do --no matter it's global or win-local
    for i = 0, vim.fn.argc() - 1 do
      table.insert(candidates, string.format("#%d %s", i, vim.fn.argv(i)))
    end
    if #candidates == 0 then return jelly.info("empty arglist") end
  end

  ui(candidates, function(line)
    local arg = assert(select(1, string.match(line, "^#%d+ (.+)$")))
    ex.cmd("edit", arg)
  end)
end

return M
