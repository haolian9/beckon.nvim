local ffi = require("ffi")

local fs = require("infra.fs")

ffi.cdef([[
  double rankToken(
    const char *str, const char *filename, const char *token,
    bool case_sensitive, bool strict_path
  );
]])

local C
do
  local lua_root = fs.resolve_plugin_root("beckon", "fuzzymatch.lua")
  local root = fs.parent(fs.parent(lua_root))
  C = ffi.load(fs.joinpath(root, "zig-out/lib/libzf.so"), false)
end

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

---@param candidates string[]
---@param token string
---@return string[]
return function(candidates, token)
  assert(token ~= nil)
  if token == "" then return candidates end

  ---@type {[1]: integer, [2]: integer}[] @[(index, rank)]
  local ranks = {}
  for i, file in ipairs(candidates) do
    local rank = rank_token(file, nil, token, false, false)
    if rank ~= -1 then table.insert(ranks, { i, rank }) end
  end
  if #ranks == 0 then return {} end

  ---rank high->low
  table.sort(ranks, function(a, b) return a[2] < b[2] end)

  local matches = {}
  for _, tuple in ipairs(ranks) do
    table.insert(matches, candidates[tuple[1]])
  end

  return matches
end
