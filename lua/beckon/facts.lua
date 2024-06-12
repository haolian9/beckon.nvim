local M = {}

local fs = require("infra.fs")
local highlighter = require("infra.highlighter")

local api = vim.api

do
  local lua_root = fs.resolve_plugin_root("beckon", "facts.lua")
  M.root = fs.parent(fs.parent(lua_root))
end

do
  local hi = highlighter(0)
  if vim.go.background == "light" then
    hi("BeckonFocusLine", { fg = 8, bg = 222 })
    hi("BeckonToken", { fg = 1, bold = true })
  else
    hi("BeckonFocusLine", { fg = 0, bg = 178 })
    hi("BeckonToken", { fg = 9, bold = true })
  end
end

do
  local ns = api.nvim_create_namespace("beckon:floatwin")
  local hi = highlighter(ns)
  if vim.go.background == "light" then
    hi("NormalFloat", { fg = 0 })
    hi("WinSeparator", { fg = 243 })
    hi("EndOfBuffer", { fg = 15 })
  else
    hi("NormalFloat", { fg = 7 })
    hi("WinSeparator", { fg = 243 })
    hi("EndOfBuffer", { fg = 0 })
  end

  M.floatwin_ns = ns
end

M.xm_query_ns = api.nvim_create_namespace("beckon:xm:query")
M.xm_focus_ns = api.nvim_create_namespace("beckon:xm:focus")
M.xm_hi_ns = api.nvim_create_namespace("beckon:xm:hi")
M.onkey_ns = api.nvim_create_namespace("beckon:onkey")

--in milliseconds
M.update_interval = 125

return M
