local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- lk optical flow
local im_size = { 1920, 1080 }

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

local inpt = L.input(L.tuple(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]), L.array2d(L.fixed(9, 0), im_size[1], im_size[2])))
local I = L.index(inpt, 1)
local J = L.index(inpt, 2)

-- compute image gradients
local Ix = conv(dx)(I)
local Iy = conv(dy)(I)

-- multiply gradients together
local IxIx = L.map(L.mul())(L.zip()(L.concat(Ix, Ix)))
local IxIy = L.map(L.mul())(L.zip()(L.concat(Ix, Iy)))
local IyIy = L.map(L.mul())(L.zip()(L.concat(Iy, Iy)))

local IxIx = L.stencil(-1, -1, 3, 3)(IxIx)
local IxIy = L.stencil(-1, -1, 3, 3)(IxIy)
local IyIy = L.stencil(-1, -1, 3, 3)(IyIy)

-- average the gradients for 2x2 structure tensor
local A11 = L.map(L.reduce(L.add()))(IxIx)
local A12 = L.map(L.reduce(L.add()))(IxIy)
local A21 = A12
local A22 = L.map(L.reduce(L.add()))(IyIy)

local diag = L.zip()(L.concat(A11, A22))

-- calculate det(A)
local d1 = L.map(L.mul())(diag)
local d2 = L.map(L.mul())(L.zip()(L.concat(A12, A21)))
local det = L.map(L.sub())(L.zip()(L.concat(d1, d2)))

-- time iterations (only 1 for now, stencil offset in J changes based on vx and vy for following iterations)
-- time derivative portion of flow
local It = L.map(L.sub())(L.zip()(inpt))

local IxIt = L.map(L.mul())(L.zip()(L.concat(Ix, It)))
local IyIt = L.map(L.mul())(L.zip()(L.concat(Iy, It)))

local IxIt = L.stencil(-1, -1, 3, 3)(IxIt)
local IyIt = L.stencil(-1, -1, 3, 3)(IyIt)

-- average the time gradients
local sum_IxIt = L.map(L.reduce(L.add()))(IxIt)
local sum_IyIt = L.map(L.reduce(L.add()))(IyIt)

-- pixel velocities
local vx = L.map(L.mul())(L.zip()(L.concat(det, sum_IxIt)))
local vy = L.map(L.mul())(L.zip()(L.concat(det, sum_IyIt)))

local res = L.zip()(L.concat(vx, vy))
local mod = L.lambda(res, inpt)

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
   inFile = "1080p.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
