local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- unsharp mask
-- local im_size = { 32, 32 }
local im_size = { 1920, 1080 }

local function conv()
   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(-1, -1, 4, 4)(pad)

   local function conv()
      local I = L.input(L.array2d(L.fixed(9, 0), 4, 4))
      local taps = L.const(L.array2d(L.fixed(9, 0), 4, 4), {
                              {  4, 14, 14,  4 },
                              { 14, 32, 32, 14 },
                              { 14, 32, 32, 14 },
                              {  4, 14, 14,  4 }})
      local c = L.chain(L.map(L.mul()), L.reduce(L.add()))
      return L.lambda(c(L.zip()(L.concat(I, taps))), I)
   end

   local conv = L.map(conv())(st)
   local conv = L.chain(L.map(L.shift(8)), L.map(L.trunc(9, 0)))(conv)
   local m = L.crop(0, 0, 0, 0)(conv)
   -- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
   local mod = L.lambda(m, I)
   return mod
end

local function scale()
   local function div()
      local factor = 16
      local x = L.input(L.fixed(9, 0))
      local c = L.const(L.fixed(9, 0), factor)
      local div = L.lambda(L.div()(L.concat(x, c)), x)
      return div
   end

   local function shr()
      local factor = 4
      local x = L.input(L.fixed(9, 0))
      local shr = L.lambda(L.shift(factor)(x), x)
      return shr
   end

   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local mod = L.lambda(L.map(shr())(I), I)
   return mod
end

local function diff(I, J)
   local IJ = L.zip()(L.concat(I, J))
   local diff = L.map(L.sub())(IJ)
   return diff
end

local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local blurred = conv()(I)
local scaled = scale()(blurred)
local buffered = L.buffer(16)(I)
local sharp = diff(buffered, scaled)
local mod = L.lambda(sharp, I)

G(mod)

-- translate to rigel and optimize
local res
local util = P.reduction_factor(mod, rate)
res = P.translate(mod)
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
   -- inFile = "box_32.raw", inSize = in_size,
   inFile = "1080p.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 300000, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
