local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- strided convolution implemented as conv -> downsample
-- it would be more efficient to do the downsample on the stencil
-- but the optimization passes can also make this peephole optimization

-- convolution
local im_size = { 32, 32 }
-- local pad_size = { im_size[1]+16, im_size[2]+3 }
local I = L.input(L.array2d(L.fixed(16, 0), im_size[1], im_size[2]))
local pad = L.pad(0, 0, 0, 0)(I)
-- local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)

local pad_size = im_size
local taps = L.const(L.array2d(L.fixed(16, 0), 4, 4), {
                        {  4, 14, 14,  4 },
                        { 14, 32, 32, 14 },
                        { 14, 32, 32, 14 },
                        {  4, 14, 14,  4 }})
local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
local st_wt = L.zip_rec()(L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local remap = L.chain(conv, L.map(L.shift(8)))
local strided = L.downsample(4, 4)(remap(st_wt))
local m = L.crop(0, 0, 0, 0)(strided)
-- local m = L.crop(8, 8, 2, 1)(remap(st_wt))
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

R.harness{
   fn = res,
   inFile = "box_32.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
