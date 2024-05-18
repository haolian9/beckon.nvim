local M = {}

local highlighter = require("infra.highlighter")

local api = vim.api

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

return M
