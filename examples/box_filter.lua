local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

-- box filter
local im_size = { 32, 32 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local conv = L.map(L.reduce(L.add()))
local m = L.crop(8, 8, 2, 1)(conv(st))
local mod = L.lambda(m, I)

local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

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
   outFile = "box_filter", outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}
