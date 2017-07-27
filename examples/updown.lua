local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

-- map -> upsample -> map -> downsample -> map
local x = L.input(L.uint8())
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.uint8(), 30))), x)

local im_size = { 32, 32 }
local x0 = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local x2 = L.upsample(2, 2)(x1)
local x3 = L.map(add_c)(x2)
local x4 = L.downsample(2, 2)(x3)
local x5 = L.map(add_c)(x4)
local mod = L.lambda(x5, x0)

-- utilization
local elem_rate = { 2, 1 }
local util = P.reduction_factor(mod, elem_rate)

-- passes
local res
res = P.translate(mod)
res = P.streamify(res, elem_rate)
res = P.transform(res, util)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)

-- passes v2
local res
res = P.translate(mod)
res = P.transform(res, util)
res = P.streamify(res, elem_rate)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)

-- print(res:toVerilog())

R.harness{
   fn = res,
   -- backend = "verilog",
   inFile = "box_32.raw", inSize = im_size,
   outFile = "updown", outSize = im_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}
