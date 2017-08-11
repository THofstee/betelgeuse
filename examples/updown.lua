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

local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

-- utilization
local rates = {
   { 1, 16 },
   { 1,  8 },
   { 1,  4 },
   { 1,  2 },
   { 1,  1 },
   { 2,  1 },
   { 4,  1 }
}

local res = {}
for i,rate in ipairs(rates) do
   local util = P.reduction_factor(mod, rate)
   res[i] = P.translate(mod)
   res[i] = P.transform(res[i], util)
   res[i] = P.streamify(res[i], elem_rate)
   res[i] = P.peephole(res[i])
end

R.harness{
   fn = res[3],
   inFile = "box_32.raw", inSize = in_size,
   outFile = "updown", outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}
