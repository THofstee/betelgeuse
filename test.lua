local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- harris corner
local im_size = { 32, 32 }

local dx = L.const(L.array2d(L.fixed(9, 0), 3, 3), {
                      { 1, 0, -1 },
                      { 2, 0, -2 },
                      { 1, 0, -1 }})

local dy = L.const(L.array2d(L.fixed(9, 0), 3, 3), {
                      {  1,  2,  1 },
                      {  0,  0,  0 },
                      { -1, -2, -1 }})

local gaussian = L.const(L.array2d(L.fixed(9, 0), 3, 3), {
                      { 20, 32, 20 },
                      { 32, 48, 32 },
                      { 20, 32, 20 }})

-- local gaussian = L.const(L.array2d(L.fixed(9, 0), 5, 5), {
--                       { 1,  4,  6,  4, 1 },
--                       { 4, 15, 24, 15, 4 },
--                       { 6, 24, 40, 24, 6 },
--                       { 4, 15, 24, 15, 4 },
--                       { 1,  4,  6,  4, 1 }})

local function conv(taps)
   local pad_size = im_size
   -- local pad_size = { im_size[1]+16, im_size[2]+3 }
   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(-1, -1, 3, 3)(pad)
   local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
   local st_wt = L.zip_rec()(L.concat(st, wt))
   local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
   -- local conv = L.chain(conv, L.map(div256()), L.map(L.trunc(8)))
   local m = L.crop(0, 0, 0, 0)(conv(st_wt))
   -- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
   local mod = L.lambda(m, I)
   return mod
end

local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))

-- compute image gradients
local Ix = conv(dx)(I)

local mod = L.lambda(Ix, I)

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

-- return the pre-translated module
return mod
