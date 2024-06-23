local buflines = require("infra.buflines")
local itertools = require("infra.itertools")
local its = require("infra.its")
local ni = require("infra.ni")
local rifts = require("infra.rifts")
local unsafe = require("infra.unsafe")

local Beckon = require("beckon.Beckon")
local facts = require("beckon.facts")

---keep the same as puff.select
---@param purpose string
---@param bufnr integer
local function open_win(purpose, bufnr)
  local _ = purpose

  local win_height, win_width
  do
    local line_count = buflines.count(bufnr)
    local line_max = 0
    for _, len in unsafe.linelen_iter(bufnr, itertools.range(line_count)) do
      if len > line_max then line_max = len end
    end

    win_height = line_count
    win_width = line_max + 1
  end

  local winopts = { relative = "cursor", row = 1, col = 0, width = win_width, height = win_height }
  local winid = rifts.open.win(bufnr, true, winopts)

  return winid
end

---@class beckon.select.Opts
---@field prompt? string
---@field format_item? fun(item:string):string
---@field kind? string
---@field open_win? beckon.OpenWin

---CAUTION: callback wont be called when user cancels (due to Beckon current impl)
---@generic T
---@param entries T[]
---@param opts beckon.select.Opts
---@param on_select  fun(entry:T?, row:integer?, action:beckon.Action) @row:1-based
return function(entries, opts, on_select)
  if opts.format_item == nil then opts.format_item = function(s) return s end end

  ---@type string[] @pattern="{entry} (index)"
  local candidates = its(entries) --
    :enumerate1()
    :mapn(function(i, ent) return string.format("%s (%d)", opts.format_item(ent), i) end)
    :tolist()

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
