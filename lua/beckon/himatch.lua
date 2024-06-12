local itertools = require("infra.itertools")
local its = require("infra.its")
local jelly = require("infra.jellyfish")("beckon.himatch", "debug")

local unsafe = require("beckon.unsafe")

---@class beckon.himatch.Opts
---@field strict_path? boolean @nil=false
---@field max_matches? integer @nil=8

---@param indices integer[]
---@return [integer,integer][] @全闭区间
local function to_consecutive_ranges(indices)
  local ranges = {}

  local iter = itertools.iter(indices)

  local prev = iter()
  local start = prev
  for next in iter do
    if next == prev + 1 then
      prev = next
    else
      table.insert(ranges, { start, prev })
      prev, start = next, next
    end
  end
  if indices[#indices] == prev then table.insert(ranges, { start, prev }) end

  return ranges
end

---@param opts? beckon.himatch.Opts
---@return beckon.himatch.Opts
local function normalize_opts(opts)
  if opts == nil then opts = {} end
  if opts.strict_path == nil then opts.strict_path = false end
  if opts.max_matches == nil then opts.max_matches = 8 end
  return opts
end

---defaults
---* no case sensitive
---* no strict path
---
---@param strings string[]|fun():string?
---@param token string
---@param opts? beckon.himatch.Opts
---@return fun():integer[][] @ranges of highlight indices; 0-based; 全闭区间
return function(strings, token, opts) --
  assert(token ~= nil)
  opts = normalize_opts(opts)

  local iter = its(strings)

  iter:map(function(str)
    local indices = unsafe.highlight_token(str, nil, token, false, opts.strict_path, opts.max_matches)
    if #indices == 0 then return jelly.fatal("unreachable", "no his for str=%s", str) end
    return indices
  end)

  iter:map(function(indices)
    local ranges = to_consecutive_ranges(indices)
    if #ranges == 0 then return jelly.fatal("unreachable", "no consecutive ranges for indices=%s", indices) end
    return ranges
  end)

  return iter:unwrap()
end
