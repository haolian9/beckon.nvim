local buflines = require("infra.buflines")
local its = require("infra.its")
local jelly = require("infra.jellyfish")("beckon.beckonize", "debug")
local LRU = require("infra.LRU")
local mi = require("infra.mi")
local ni = require("infra.ni")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local wincursor = require("infra.wincursor")

local InvertBeckon = require("beckon.InvertBeckon")

local last_queries = LRU(512)

---limits:
---* assert: 3 < buf.lines < 9999
---* assert: win.height >= 2
---* skip: #line == 0
---* truncate: #line>300
---@param host_winid? integer
---@param callback? fun(lnum:integer, action:beckon.Action) @nil=move-cursor
---@param opts? {remember:boolean?}
return function(host_winid, callback, opts)
  host_winid = mi.resolve_winid_param(host_winid)
  callback = callback or function(lnum) wincursor.go(host_winid, lnum, 0) end
  opts = opts or {}

  local host_bufnr = ni.win_get_buf(host_winid)

  local line_count = buflines.count(host_bufnr)
  if not (line_count > 3 and line_count < 9999) then return jelly.warn("too few/many lines to beckonize") end

  ---@type {height:integer, width:integer, relative:string}
  local host_wincfg = ni.win_get_config(host_winid)
  if host_wincfg.height < 2 then return jelly.warn("not enough height to beckonize") end

  local function open_win(_, beckon_bufnr)
    local winopts = { relative = "win", row = 0, col = 0 }
    winopts.width = host_wincfg.width
    winopts.height = host_wincfg.height
    local beckon_winid = rifts.open.win(beckon_bufnr, true, winopts)
    ni.win_set_hl_ns(beckon_winid, rifts.ns)
    prefer.wo(beckon_winid, "wrap", false)
    return beckon_winid
  end

  local default_query
  if opts.remember then default_query = last_queries[host_winid] end

  local lines = its(buflines.iter(host_bufnr)) --
    :filtern(function(line, _) return #line > 0 end)
    :mapn(function(line, lnum) return string.format("%s (%d)", string.sub(line, 1, 300), lnum) end)
    :tolist()

  InvertBeckon("beckon", lines, function(query, action, line)
    local lnum = assert(string.match(line, "%((%d+)%)$"))
    last_queries[host_winid] = query
    callback(lnum, action)
  end, { open_win = open_win, default_query = default_query })
end
