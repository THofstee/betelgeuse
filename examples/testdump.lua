local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local G = require 'graphview'
local D = require 'dump'

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
G(mod)

local s = D(mod)
print(s)
G(assert(loadstring(s))())

local rate = { 1, 1 }
local res = P.opt(mod, rate)
G(res)

local s = D(res)
print(s)
G(assert(loadstring(s))())

local r = P.rigel(res)
G(r)

local s = D(r)
print(s)
G(assert(loadstring(s))())
