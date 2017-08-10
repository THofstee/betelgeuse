local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'

-- convolution
local im_size = { 32, 32 }
local pad_size = { im_size[1]+16, im_size[2]+3 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local taps = L.const(L.array2d(L.uint8(), 4, 4), {
						{  4, 14, 14,  4 },
						{ 14, 32, 32, 14 },
						{ 14, 32, 32, 14 },
						{  4, 14, 14,  4 }})
local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
local st_wt = L.zip_rec()(L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local m = L.crop(8, 8, 2, 1)(conv(st_wt))
local mod = L.lambda(m, I)

local gv = require 'graphview'
gv(mod)
-- assert(false)

local elem_size = { 1, 4 }
local util = P.reduction_factor(mod, elem_size)

-- passes
local res
res = P.translate(mod)
res = P.transform(res, util)
res = P.streamify(res, elem_size)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)

local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

local R = require 'rigelSimple'
R.harness{
   fn = res,
   inFile = "box_32.raw", inSize = in_size,
   outFile = "conv", outSize = out_size,
   earlyOverride = 48000, -- downsample is variable latency, overestimate cycles
}
