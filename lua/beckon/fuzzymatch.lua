local unsafe = require("beckon.unsafe")

---@param candidates string[]
---@param token string
---@return string[]
return function(candidates, token)
  if token == "" then return candidates end

  ---@type {[1]: integer, [2]: integer}[] @[(index, rank)]
  local ranks = {}
  do
    -- local filename = ffi.new("char[1]")
    for i, file in ipairs(candidates) do
      local rank = unsafe.rankToken(file, nil, token, false, false)
      if rank ~= -1 then table.insert(ranks, { i, rank }) end
    end
    if #ranks == 0 then return {} end
  end

  ---rank high->low
  table.sort(ranks, function(a, b) return a[2] < b[2] end)

  local matches = {}
  for _, tuple in ipairs(ranks) do
    table.insert(matches, candidates[tuple[1]])
  end

  return matches
end
