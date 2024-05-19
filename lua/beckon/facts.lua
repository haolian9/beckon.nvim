local M = {}

local fs = require("infra.fs")
local highlighter = require("infra.highlighter")

local api = vim.api

do
  local lua_root = fs.resolve_plugin_root("beckon", "facts.lua")
  M.root = fs.parent(fs.parent(lua_root))
end

do
  local ns = api.nvim_create_namespace("beckon:floatwin")
  local hi = highlighter(ns)
  if vim.go.background == "light" then
    hi("EndOfBuffer", { fg = 15 })
  else
    hi("EndOfBuffer", { fg = 0 })
  end

  M.floatwin_ns = ns
end

M.querysuffix_ns = api.nvim_create_namespace("beckon:querysuffix")

--in milliseconds
M.update_interval = 125

return M
