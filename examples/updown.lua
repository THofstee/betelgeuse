local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- map -> upsample -> map -> downsample -> map
local x = L.input(L.fixed(9, 0))
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.fixed(9, 0), 30))), x)

local im_size = { 1920, 1080 }
local x0 = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local x2 = L.upsample(2, 1)(x1)
local x3 = L.map(add_c)(x2)
local x4 = L.downsample(2, 1)(x3)
local x5 = L.map(add_c)(x4)
local mod = L.lambda(x5, x0)
-- G(mod)

-- optimize
local res = P.opt(mod, rate)
G(res)

-- translate to rigel and run
local r,s = P.rigel(res)

local inspect = require 'inspect'
local f = assert(io.open(string.format("dbg/%s-%s.txt", rate[1], rate[2]), "w"))
f:write(inspect(r, {
                   process = function(item, path)
                      if path[#path] == 'loc' then return nil end
                      if path[#path] == inspect.METATABLE then return nil end
                      if path[#path] == 'sdfRate' then return nil end
                      if path[#path] == 'globals' then return nil end
                      if path[#path] == 'globalMetadata' then return nil end
                      if path[#path] == 'makeSystolic' then return nil end
                      -- if path[#path] == 'name' then return nil end
                      if path[#path] == 'stateful' then return nil end
                      if path[#path] == 'delay' then return nil end
                      if path[#path] == 'type' then return tostring(item) end
                      if path[#path] == 'inputType' then return tostring(item) end
                      if path[#path] == 'outputType' then return tostring(item) end
                      return item
                   end
}))

G(r)
s("1080p.raw")

-- return the unoptimized module
return mod
