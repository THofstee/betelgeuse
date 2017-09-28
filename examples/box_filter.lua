local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- box filter
local im_size = { 32, 32 }
local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local conv = L.map(L.reduce(L.add(true)))
local m = conv(st)
local m = L.map(L.shift(4, true))(m)
local m = L.map(L.trunc(8, 0))(m)
local m = L.crop(8, 8, 2, 1)(m)
local mod = L.lambda(m, I)

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
   inFile = "impulse_32.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
