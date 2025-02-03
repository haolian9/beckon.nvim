local M = {}

local highlighter = require("infra.highlighter")
local ni = require("infra.ni")
local resolve_plugin_root = require("infra.resolve_plugin_root")

M.root = resolve_plugin_root("beckon", "facts.lua")

do
  local hi = highlighter(0)

  --CAUTION: DO NOT SET fg for BeckonFocusLine, it causes highlighting issue, when BeckonToken is at the begining of a line

  if vim.go.background == "light" then
    hi("BeckonFocusLine", { bg = 222 })
    hi("BeckonToken", { fg = 1, bold = true })
  else
    hi("BeckonFocusLine", { bg = 3 })
    hi("BeckonToken", { fg = 9, bold = true })
  end

  assert(ni.get_hl(0, { name = "BeckonFocusLine", create = false }).fg == nil)
end

do
  local ns = ni.create_namespace("beckon:floatwin")
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

M.xm_query_ns = ni.create_namespace("beckon:xm:query")
M.xm_focus_ns = ni.create_namespace("beckon:xm:focus")
M.xm_hi_ns = ni.create_namespace("beckon:xm:hi")
M.onkey_ns = ni.create_namespace("beckon:onkey")

--in milliseconds
M.update_interval = 125

return M
