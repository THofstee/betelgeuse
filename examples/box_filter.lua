local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'

-- box filter
local im_size = { 16, 32 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local conv = L.map(L.reduce(L.add()))
local m = L.crop(8, 8, 2, 1)(conv(st))
local mod = L.lambda(m, I)

local elem_size = { 1, 1 }
local util = P.reduction_factor(mod, elem_size)

local res
res = P.translate(mod)
-- res = P.transform(res, util)
res = P.streamify(res, elem_size)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)
