local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 2 }

-- box filter
-- local im_size = { 32, 32 }
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
-- local pad = L.pad(8, 8, 2, 1)(I)
local pad = L.pad(0, 0, 0, 0)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local conv = L.map(L.reduce(L.add(true)))
local m = conv(st)
local m = L.map(L.shift(4, true))(m)
local m = L.map(L.trunc(8, 0))(m)
-- local m = L.crop(8, 8, 2, 1)(m)
local m = L.crop(0, 0, 0, 0)(m)
local mod = L.lambda(m, I)

G(mod)

local util = P.reduction_factor(mod, rate)
G(P.transform(P.translate(mod), util))
-- optimize
local res = P.opt(mod, rate)
G(res)

-- translate to rigel and run
local r,s = P.rigel(res)
G(r)

-- local D = require 'dump'
-- local function write_to_file(filename, str)
--    local f = assert(io.open(filename, "w"))
--    f:write(str)
--    f:close()
-- end
-- write_to_file("dbg/dump-ir.lua", D(res))
-- write_to_file("dbg/dump-rigel.lua", D(r))
-- G(assert(loadstring(D(r)))())

s("1080p.raw")

-- return the unoptimized module
return mod
