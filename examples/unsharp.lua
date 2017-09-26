local L = require 'betelgeuse.lang'

local im_size = { 1920, 1080 }

local function conv()
   local pad_size = im_size
   -- local pad_size = { im_size[1]+16, im_size[2]+3 }
   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(-1, -1, 4, 4)(pad)
   local taps = L.const(L.array2d(L.fixed(9, 0), 4, 4), {
                           {  4, 14, 14,  4 },
                           { 14, 32, 32, 14 },
                           { 14, 32, 32, 14 },
                           {  4, 14, 14,  4 }})
   local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
   local st_wt = L.zip_rec()(L.concat(st, wt))
   local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
   -- local conv = L.chain(conv, L.map(div256()), L.map(L.trunc(8)))
   local m = L.crop(0, 0, 0, 0)(conv(st_wt))
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
local sharp = diff(I, scaled)
local mod = L.lambda(sharp, I)


local gv = require 'graphview'
gv(mod)


local P = require 'betelgeuse.passes'

-- utilization
local rates = {
   -- { 1, 32 },
   -- { 1, 16 },
   -- { 1,  8 },
   -- { 1,  4 },
   -- { 1,  2 },
   { 1,  1 },
   -- { 2,  1 },
   -- { 4,  1 },
   -- { 8,  1 },
}

local res = {}
for i,rate in ipairs(rates) do
   local util = P.reduction_factor(mod, rate)
   res[i] = P.translate(mod)
   -- res[i] = P.transform(res[i], util)
   -- res[i] = P.streamify(res[i], rate)
   -- res[i] = P.peephole(res[i])
end

gv(res[1])

local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

return mod
