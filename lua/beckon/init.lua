local M = {}

local fn = require("infra.fn")
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
    end

    ui(candidates, function(line)
      local nr
      nr = assert(select(1, string.match(line, "^#(%d+) ")), line)
      nr = assert(tonumber(nr))

      api.nvim_win_set_buf(0, nr)
    end)
  end
end

return M
