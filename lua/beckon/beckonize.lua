local buflines = require("infra.buflines")
local its = require("infra.its")
local jelly = require("infra.jellyfish")("beckon.beckonize", "debug")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local wincursor = require("infra.wincursor")

local Beckon = require("beckon.Beckon")

local api = vim.api

---limits:
---* assert: 3 < buf.lines < 999
---* assert: win.height >= 2
---* skip: #line == 0
---* truncate: #line>300
---@param host_winid integer
---@param callback? fun(row:integer, action:beckon.Action) @nil=move-cursor
return function(host_winid, callback)
  if callback == nil then
    function callback(lnum) wincursor.go(host_winid, lnum, 0) end
  end

  local host_bufnr = api.nvim_win_get_buf(host_winid)

  local line_count = buflines.count(host_bufnr)
  if not (line_count > 3 and line_count < 999) then return jelly.warn("too few/many lines to beckonize") end

  ---@type {height:integer, width:integer, relative:string}
  local host_wincfg = api.nvim_win_get_config(host_winid)
  if host_wincfg.height < 2 then return jelly.warn("not enough height to beckonize") end

  local function open_win(_, beckon_bufnr)
    local winopts = { relative = "win", row = 0, col = 0 }
    winopts.width = host_wincfg.width
    winopts.height = host_wincfg.height
    local beckon_winid = rifts.open.win(beckon_bufnr, true, winopts)
    api.nvim_win_set_hl_ns(beckon_winid, rifts.ns)
    prefer.wo(beckon_winid, "wrap", false)
    return beckon_winid
  end

  local lines = its(buflines.iter(host_bufnr)) --
    :filtern(function(line, _) return #line > 0 end)
    :mapn(function(line, lnum) return string.format("%s (%d)", string.sub(line, 1, 300), lnum) end)
    :tolist()

  Beckon("beckon", lines, function(_, action, line)
    local lnum = assert(string.match(line, "%((%d+)%)$"))
    callback(lnum, action)
  end, { open_win = open_win })
end
