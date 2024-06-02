local ffi = require("ffi")

local fs = require("infra.fs")

local facts = require("beckon.facts")

ffi.cdef([[
  double rankToken(
    const char *str, const char *filename, const char *token,
    bool case_sensitive, bool strict_path
  );
]])

local C = ffi.load(fs.joinpath(facts.root, "zig-out/lib/libzf.so"), false)

---@param str string @it will be converted to lowercase internally
---@param filename? string @meaning?
---@param token string
---@param case_sensitive boolean @false: no convert the tokens to lowercase
---@param strict_path boolean @meaning?
---@return number @-1 when no match
local function rank_token(str, filename, token, case_sensitive, strict_path)
  local rank = C.rankToken(str, filename, token, case_sensitive, strict_path)
  return assert(tonumber(rank))
end

---@class beckon.fuzzymatch.Opts
---@field strict_path? boolean @nil=false
---@field sort? 'asc'|'desc'|false @nil='asc'
---@field tostr? fun(candidate:any): string

local function compare_descent(a, b) return a[2] > b[2] end
local function compare_ascent(a, b) return a[2] < b[2] end

---@param opts? beckon.fuzzymatch.Opts
---@return beckon.fuzzymatch.Opts
local function normalize_opts(opts)
  if opts == nil then return { strict_path = false, sort = false, tostr = nil } end
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

  ---@type {[1]: integer, [2]: integer}[] @[(index, rank)]
  local ranks = {}
  for i, cand in ipairs(candidates) do
    local rank = rank_token(opts.tostr(cand), nil, token, false, opts.strict_path)
    if rank ~= -1 then table.insert(ranks, { i, rank }) end
  end
  if #ranks == 0 then return {} end

  if opts.sort == "asc" then
    table.sort(ranks, compare_ascent)
  elseif opts.sort == "desc" then
    table.sort(ranks, compare_descent)
  else
    ---no sort
  end

  local matches = {}
  for _, tuple in ipairs(ranks) do
    table.insert(matches, candidates[tuple[1]])
  end

  return matches
end
