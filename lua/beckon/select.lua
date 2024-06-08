local buflines = require("infra.buflines")
local itertools = require("infra.itertools")
local listlib = require("infra.listlib")
local rifts = require("infra.rifts")
local unsafe = require("infra.unsafe")

local Beckon = require("beckon.Beckon")
local facts = require("beckon.facts")

local api = vim.api

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

---CAUTION: callback wont be called when user cancels (due to Beckon current impl)
---@param entries string[]
---@param opts {prompt:string?, format_item:fun(entry:string):string, kind:string?, open_win:beckon.OpenWin?}
---@param callback fun(entry: string?, index: number?, action: beckon.Action) @index: 1-based
return function(entries, opts, callback)
  ---@type string[] @pattern="{entry} (index)"
  local candidates
  do
    local iter
    iter = listlib.enumerate1(entries)
    if opts.format_item then
      iter = itertools.mapn(function(i, ent) return string.format("%s (%d)", opts.format_item(ent), i) end, iter)
    else
      iter = itertools.mapn(function(i, ent) return string.format("%s (%d)", ent, i) end, iter)
    end

    candidates = itertools.tolist(iter)
  end

  local _, bufnr = Beckon("select", candidates, function(_, action, line)
    local index = assert(string.match(line, "%((%d+)%)$"))
    index = assert(tonumber(index))
    local entry = assert(entries[index])
    callback(entry, index, action)
  end, { open_win = opts.open_win or open_win })

  if opts.prompt ~= nil then --inline extmark as prompt
    api.nvim_buf_set_extmark(bufnr, facts.queryextmark_ns, 0, 0, {
      virt_text = { { opts.prompt, "Question" }, { " " } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  --cant honor the callback in autocmd bufwipeout, as Beckon closes the win before honors .on_pick
end
