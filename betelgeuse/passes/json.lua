local json = require 'json'
local memoize = require 'memoize'
local inspect = require 'inspect'

local encode = {}
local encode_mt = {
   __call = memoize(function(encode, m)
      local dispatch = m.kind
      assert(encode[dispatch], "dispatch function " .. dispatch .. " is nil")
      return encode[dispatch](m)
   end)
}
setmetatable(encode, encode_mt)

function encode.apply(m)
   print(inspect(m, {depth = 2}))
end

local function to_json(m)
   local m = m.f

   return json.encode(encode(m))
end

return to_json
