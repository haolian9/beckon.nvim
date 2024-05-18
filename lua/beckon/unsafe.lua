local M = {}

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
  local lua_root = fs.resolve_plugin_root("beckon", "unsafe.lua")
  local root = fs.parent(fs.parent(lua_root))
  C = ffi.load(fs.joinpath(root, "zig-out/lib/libzf.so"), false)
end

---@param str string
---@param filename? string
---@param token string
---@param case_sensitive boolean
---@param strick_path boolean
---@return number
function M.rankToken(str, filename, token, case_sensitive, strick_path)
  local rank = C.rankToken(str, filename, token, case_sensitive, strick_path)
  return assert(tonumber(rank))
end

return M

