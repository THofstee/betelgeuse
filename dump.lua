local bg = require 'dump.betelgeuse'
local ri = require 'dump.rigel'
local ir = require 'dump.ir'

local D = {}

local function dump(m)
   bg(m)
end

local D_mt = {
   __call = function(t, m)
      return dump(m)
   end
}

setmetatable(D, D_mt)
return D
