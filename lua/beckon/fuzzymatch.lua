local new_table = require("table.new")

local unsafe = require("beckon.unsafe")

---@class beckon.fuzzymatch.Opts
---@field strict_path? boolean @nil=false
---@field sort? 'asc'|'desc'|false @nil='asc'
---@field tostr? fun(candidate:any): string

local function compare_descent(a, b) return a[2] > b[2] end
local function compare_ascent(a, b) return a[2] < b[2] end

---@param opts? beckon.fuzzymatch.Opts
---@return beckon.fuzzymatch.Opts
local function normalize_opts(opts)
  if opts == nil then opts = {} end
  if opts.strict_path == nil then opts.strict_path = false end
  if opts.sort == nil then opts.sort = "asc" end
  if opts.tostr == nil then opts.tostr = function(str) return str end end
  return opts
end

---defaults
---* no case sensitive
---* no strict path
---* results in ascent order
---@generic T
---@param candidates T[]
---@param token string
---@param opts? beckon.fuzzymatch.Opts
---@return T[]
return function(candidates, token, opts)
  assert(token ~= nil)
  if token == "" then return candidates end

  opts = normalize_opts(opts)

  if opts.sort == false then --shortcut
    local matches = {}
    for _, cand in ipairs(candidates) do
      local rank = unsafe.rank_token(opts.tostr(cand), nil, token, false, opts.strict_path)
      if rank ~= -1 then table.insert(matches, cand) end
    end
    return matches
  end

  local ranks = {} ---@type [any,integer][] @[(candidate, rank)]
  for _, cand in ipairs(candidates) do
    local rank = unsafe.rank_token(opts.tostr(cand), nil, token, false, opts.strict_path)
    if rank ~= -1 then table.insert(ranks, { cand, rank }) end
  end
  if #ranks == 0 then return {} end

  if opts.sort == "asc" then
    table.sort(ranks, compare_ascent)
  elseif opts.sort == "desc" then
    table.sort(ranks, compare_descent)
  else
    error("unreachable")
  end

  local matches = new_table(#ranks, 0)
  for i, tuple in ipairs(ranks) do
    matches[i] = tuple[1]
  end

  return matches
end
