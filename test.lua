local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local IR = require 'betelgeuse.ir'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

-- map -> upsample -> map -> downsample -> map
local x = L.input(L.fixed(9, 0))
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.fixed(9, 0), 30))), x)

-- local im_size = { 32, 32 }
local im_size = { 1920, 1080 }
local x0 = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local x2 = L.upsample(2, 1)(x1)
local x3 = L.map(add_c)(x2)
local x4 = L.downsample(2, 1)(x3)
local x5 = L.map(add_c)(x4)
local mod = L.lambda(x5, x0)
-- G(mod)

local x0 = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local mod = L.lambda(x1, x0)

local inspect = require 'inspect'

local y = IR.input(IR.bit(9, 0))
local add_y = IR.lambda(IR.apply(IR.add(), IR.concat(y, IR.const(IR.bit(9, 0), 30))), y)

local y0 = IR.input(IR.array2d(IR.bit(9, 0), im_size[1], im_size[2]))
local y1 = IR.apply(IR.map_x(add_y, {1, 1}), y0)
local y2 = IR.apply(IR.upsample_x(2, 1), y1)
local y3 = IR.apply(IR.map_x(add_y, {1, 1}), y2)
local y4 = IR.apply(IR.downsample_x(2, 1), y3)
local y5 = IR.apply(IR.map_x(add_y, {1, 1}), y4)
local mod_y = IR.lambda(y5, y0)

-- -- translate to rigel and optimize
local res
local util = P.reduction_factor(mod, rate)
res = P.translate(mod)
res = P.transform(res, util)
res = P.fuse_reshape(res)
res = P.fuse_map(res)
res = P.fuse_concat(res)
-- res = P.peephole(res)
-- res = P.streamify(res, rate)
-- G(res.f.v.m.m)
G(res)
-- P.json(res)
-- res = P.make_mem_happy(res)
local r,s = P.rigel(res)
G(r)
s("1080p.raw")
