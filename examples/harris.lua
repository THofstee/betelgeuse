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
   local function conv2()
      local I = L.input(L.array2d(L.fixed(9, 0), 3, 3))
      local c = L.chain(L.map(L.mul()), L.reduce(L.add()))
      return L.lambda(c(L.zip()(L.concat(I, taps))), I)
   end

   local pad_size = im_size
   -- local pad_size = { im_size[1]+16, im_size[2]+3 }
   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(-1, -1, 3, 3)(pad)
   local m = L.crop(0, 0, 0, 0)(L.map(conv2())(st))
   -- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
   local mod = L.lambda(m, I)
   return mod
end

local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))

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

-- calculate k*tr(A)^2
local tr = L.map(L.add())(diag)
local tr2 = L.map(L.mul())(L.zip()(L.concat(tr, tr)))
-- local ktr2 = L.map(L.div())(L.zip()(L.concat(tr2, L.broadcast(im_size[1], im_size[2])(L.const(L.fixed(9, 0), 20)))))
-- local ktr2 = L.map(L.mul())(L.zip()(L.concat(tr2, L.broadcast(im_size[1], im_size[2])(L.const(L.fixed(0, 6), 3))))) -- hack, 1/20 is .000011... so we say 3 with 6 fixed point bits since i cant declare fixed point consts yet
local ktr2 = tr2 -- hack, just ignore the division.

-- corner response = det(A)-k*tr(A)^2
local Mc = L.map(L.sub())(L.zip()(L.concat(det, ktr2)))

local mod = L.lambda(Mc, I)

G(mod)

-- translate to rigel and optimize
local res
local util = P.reduction_factor(mod, rate)
res = P.translate(mod)
res = P.transform(res, util)
res = P.streamify(res, rate)
res = P.peephole(res)
G(res)
res = P.make_mem_happy(res)


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
