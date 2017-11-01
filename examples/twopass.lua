local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- two pass
local im_size = { 32, 32 }

local blury = L.const(L.array2d(L.fixed(9, 0), 1, 3), {
                      { 1 },
                      { 2 },
                      { 1 }})

local blurx = L.const(L.array2d(L.fixed(9, 0), 3, 1), {
                      { 1, 2, 1 }})

local dx = L.const(L.array2d(L.fixed(9, 0), 3, 1), {
                      { 1, 0, -1 }})

local function conv(s, taps)
   local function conv2()
      local I = L.input(L.array2d(L.fixed(9, 0), s[3], s[4]))
      local c = L.chain(L.map(L.mul()), L.reduce(L.add()))
      return L.lambda(c(L.zip()(L.concat(I, taps))), I)
   end

   local pad_size = im_size
   -- local pad_size = { im_size[1]+16, im_size[2]+3 }
   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(s[1], s[2], s[3], s[4])(pad)
   local m = L.crop(0, 0, 0, 0)(L.map(conv2())(st))
   -- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
   local mod = L.lambda(m, I)
   return mod
end

local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
-- local x1 = conv({ -1, 0, 3, 1 }, dx)(I)
local x1 = L.chain(conv({ -1, 0, 3, 1 }, blurx), L.map(L.shift(2)))(I)
local x2 = L.chain(conv({ 0, -1, 1, 3 }, blury), L.map(L.shift(2)))(x1)
local mod = L.lambda(x2, I)
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
   inFile = "box_32.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
