local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

local x = L.input(L.uint8())
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.uint8(), 30))), x)

-- map -> pad -> map -> crop -> map
local im_size = { 32, 32 }
local x0 = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local x2 = L.pad(8, 8, 2, 1)(x1)
local x3 = L.map(add_c)(x2)
local x4 = L.crop(8, 8, 2, 1)(x3)
local x5 = L.map(add_c)(x4)
local mod = L.lambda(x5, x0)

local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

-- passes
local elem_size = { 1, 1 }
local util = P.reduction_factor(mod, elem_size)

local res
res = P.translate(mod)
res = P.transform(res, util)
res = P.streamify(res, elem_size)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)

R.harness{
   fn = res,
   inFile = "box_32.raw", inSize = in_size,
   outFile = "padcrop", outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}
