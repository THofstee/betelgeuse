local inspect = require 'inspect'
local L = require 'lang'
local P = require 'passes'
--[[
   tests with rigel
--]]

-- add constant to image (broadcast)
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local c = L.const(L.uint8(), 1)
local bc = L.broadcast(im_size[1], im_size[2])(c)
local m = L.map(L.add())(L.zip_rec()(L.concat(I, bc)))

-- @todo: add something like betel(function(I) map(f)(I) end) that will let you declare lambdas more easily
-- @todo: add something like an extra class that when called will lower the module into rigel and give you back something
-- @todo: remove the rigel harness calls, or make a nicer way to do that
-- @todo: add some sort of support for cross-module optimizations

-- add two image streams
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local J = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local ij = L.zip_rec()(L.concat(I, J))
local m = L.map(L.add())(ij)

-- @todo: check map of zip_rec
-- @todo: this should probably return a lambda so i can use it in a map?
-- @todo: should split up generators/macros? L_wrap_macro, L_wrap_gen
-- function make_lambda(f)
--    return function(v)
-- 	  local input = L.input(v.type)
-- 	  return L.lambda(f(input), input)

--    end
-- end

-- L.apply(make_lambda(function(x) return L.concat(x, L.const(L.uint8(), 30)) end), L.input(L.uint8()))

-- box filter
local im_size = { 16, 32 }
local pad_size = { im_size[1]+16, im_size[2]+3 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local conv = L.map(L.reduce(L.add()))
local m = L.crop(8, 8, 2, 1)(conv(st))
local mod = L.lambda(m, I)

-- -- box filter conv (fork)
-- local im_size = { 16, 32 }
-- local pad_size = { im_size[1]+16, im_size[2]+3 }
-- local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
-- local pad = L.pad(8, 8, 2, 1)(I)
-- local st = L.stencil(-1, -1, 4, 4)(pad)
-- local st_wt = L.zip_rec()(L.concat(st, st))
-- local conv = L.chain(L.map(L.map(L.add())), L.map(L.reduce(L.add())))
-- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
-- local mod = L.lambda(m, I)

-- -- Two inputs, one multi rate
-- local I = L.input(L.array2d(L.uint8(), 10, 10))
-- local J = L.input(L.array2d(L.uint8(), 12, 12))
-- local I2 = L.pad(1, 1, 1, 1)(I)
-- local m = L.map(L.add())(L.concat(I2, J))

-- -- One interleaved input, fork into multi-rate for one branch, then join
-- local I = L.input(L.array2d(L.array(L.uint8(), 2), 16, 16))


local res
res = P.translate(mod)
print('--- Translate ---')
P.rates(res)
res = P.streamify(res)
print('--- Streamify ---')
P.rates(res)
res = P.transform(res)
print('--- Transform ---')
P.rates(res)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)
-- res = P.handshakes(res)
-- print('--- Handshake ---')
-- P.rates(res)

-- @todo: lucas-kanade
-- @todo: histogram
