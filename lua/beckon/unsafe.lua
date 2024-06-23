local M = {}

local ffi = require("ffi")

local fs = require("infra.fs")

local facts = require("beckon.facts")

ffi.cdef([[
  double rankToken(
    const char *str, const char *filename, const char *token,
    bool case_sensitive, bool strict_path
  );

  size_t highlightToken(
    const char *str, const char *filename, const char *token,
    bool case_sensitive, bool strict_path,
    size_t *matches, size_t matches_len
  );
]])

local C = ffi.load(fs.joinpath(facts.root, "zig-out/lib/libzf.so"), false)

---@param str string @it will be converted to lowercase internally
---@param filename? string @meaning?
---@param token string
---@param case_sensitive boolean @false: no convert the tokens to lowercase
---@param strict_path boolean @meaning?
---@return number @-1 when no match
function M.rank_token(str, filename, token, case_sensitive, strict_path)
  local rank = C.rankToken(str, filename, token, case_sensitive, strict_path)
  return assert(tonumber(rank))
end

---@param str string @it will be converted to lowercase internally
---@param filename? string @meaning?
---@param token string
---@param case_sensitive boolean @false: no convert the tokens to lowercase
---@param strict_path boolean @meaning?
---@param max_matches integer
---@return integer[] indices @0-based
function M.highlight_token(str, filename, token, case_sensitive, strict_path, max_matches)
  local matches = ffi.new("size_t[?]", max_matches)
  local n = C.highlightToken(str, filename, token, case_sensitive, strict_path, matches, max_matches)

  local indices = {}
  for i = 1, tonumber(n) do
    local index = (matches + i - 1)[0]
    indices[i] = assert(tonumber(index))
  end

  return indices
end

return M
