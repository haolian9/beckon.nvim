local its = require("infra.its")
local ni = require("infra.ni")
local rifts = require("infra.rifts")

local Beckon = require("beckon.Beckon")
local facts = require("beckon.facts")

---@class beckon.select.Opts
---@field prompt? string
---@field format_item? fun(item:string):string
---@field kind? string
---@field open_win? beckon.OpenWin

---CAUTION: callback wont be called when user cancels (due to Beckon current impl)
---@generic T
---@param entries T[]
---@param opts beckon.select.Opts
---@param on_select  fun(entry:T?, index:integer?, action?:beckon.Action) @index:1-based
return function(entries, opts, on_select)
  if #entries == 0 then return on_select() end

  if opts.format_item == nil then opts.format_item = function(s) return s end end

  ---@type string[] @pattern="{entry} (index)"
  local candidates = its(entries) --
    :enumerate1()
    :mapn(function(i, ent) return string.format("%s (%d)", opts.format_item(ent), i) end)
    :tolist()

  local open_win
  if opts.open_win then
    open_win = opts.open_win
  else
    open_win = function(_, bufnr)
      local height = #entries + 1 -- query line

      --todo: avoid evaluating opts.format_item twice
      local width = its(entries):map(opts.format_item):map(string.len):max()
      width = width + 2 --signcolumn=yes:1
      width = width + #" (99) "
      width = math.max(width, 20) --prompt could be long

      local winopts = { relative = "cursor", row = 1, col = 0, width = width, height = height }
      local winid = rifts.open.win(bufnr, true, winopts)
      ni.win_set_hl_ns(winid, facts.floatwin_ns)

      return winid
    end
  end

  local _, bufnr = Beckon("select", candidates, function(_, action, line)
    local index = assert(string.match(line, "%((%d+)%)$"))
    index = assert(tonumber(index))
    local entry = assert(entries[index])
    on_select(entry, index, action)
  end, { open_win = opts.open_win or open_win })

  if opts.prompt ~= nil then --inline extmark as prompt
    ni.buf_set_extmark(bufnr, facts.xm_query_ns, 0, 0, {
      virt_text = { { opts.prompt, "Question" }, { " " } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  --cant honor the callback in autocmd bufwipeout, as Beckon closes the win before honors .on_pick
end
