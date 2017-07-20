local L = require 'lang'
local P = require 'passes'

-- map -> upsample -> map -> downsample -> map
local x = L.input(L.uint8())
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.uint8(), 30))), x)

local im_size = { 2, 2 }
local x0 = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local x1 = L.map(add_c)(x0)
local x2 = L.upsample(2, 1)(x1)
local x3 = L.map(add_c)(x2)
local x4 = L.downsample(2, 1)(x3)
local x5 = L.map(add_c)(x4)
local mod = L.lambda(x5, x0)

-- passes
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
