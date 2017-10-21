local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- image mip pyramid
local im_size = { 32, 32 }
local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local x0 = I
local x1 = L.downsample(2, 2)(x0)
local x2 = L.downsample(2, 2)(x1)
local x3 = L.downsample(2, 2)(x2)
local x4 = L.downsample(2, 2)(x3)
local y = L.concat(x0, x1, x2, x3, x4)

print(y.type)

local mod = L.lambda(y, I)
G(mod)

-- translate to rigel and optimize
local res
local util = P.reduction_factor(mod, rate)
res = P.translate(mod)
G(res)
res = P.transform(res, util)
res = P.streamify(res, rate)
res = P.peephole(res)
res = P.make_mem_happy(res)
G(res)

-- call harness
local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

local fname = arg[0]:match("([^/]+).lua")

R.harness{
   backend = 'verilog',
   fn = res,
   inFile = "box_32.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
