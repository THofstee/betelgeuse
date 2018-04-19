local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local G = require 'graphview'
local D = require 'dump'
G.render = true

local loadstring = loadstring or load

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

local function write_to_file(filename, str)
   local f = assert(io.open(filename, "w"))
   f:write(str)
   f:close()
end

local s = D(mod)
-- print(s)
write_to_file("dbg/dump-bg.lua", s)
G(assert(loadstring(s))())

local res = P.translate(mod)
local s = D(res)
write_to_file("dbg/dump-translate.lua", s)

G(res)

local rate = { 1, 2 }

local util = P.reduction_factor(mod, rate)
local res = P.transform(res, util)
local s = D(res)
write_to_file("dbg/dump-transform.lua", s)
write_to_file("dbg/ir.txt", require'inspect'(res))

G(res)

local res = P.fuse_reshape(res)
local s = D(res)
write_to_file("dbg/dump-reshape.lua", s)

local res = P.fuse_map(res)
local s = D(res)
write_to_file("dbg/dump-map.lua", s)

local res = P.opt(mod, rate)
G(res)

local s = D(res)
-- print(s)
write_to_file("dbg/dump-ir.lua", s)
G(assert(loadstring(s))())

G(res.f)

local r = P.rigel(res)
G(r)

local s = D(r)
-- print(s)
write_to_file("dbg/dump-rigel.lua", s)
G(assert(loadstring(s))())
