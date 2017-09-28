local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- map -> upsample -> map -> downsample -> map
local x = L.input(L.fixed(9, 0))
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.fixed(9, 0), 30))), x)

local im_size = { 32, 32 }
local x0 = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local x2 = L.upsample(2, 2)(x1)
local x3 = L.map(add_c)(x2)
local x4 = L.downsample(2, 2)(x3)
local x5 = L.map(add_c)(x4)
local mod = L.lambda(x5, x0)

-- translate to rigel and optimize
local res
local util = P.reduction_factor(mod, rate)
res = P.translate(mod)
res = P.transform(res, util)
res = P.streamify(res, rate)
res = P.peephole(res)
res = P.make_mem_happy(res)

-- call harness
local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

local fname = arg[0]:match("([^/]+).lua")
arg = {}

R.harness{
   fn = res,
   inFile = "box_32.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
