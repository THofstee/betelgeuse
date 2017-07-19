local L = require 'lang'
local P = require 'passes'

-- map -> upsample -> map
local const_val = 30
local x = L.input(L.uint8())
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.uint8(), 30))), x)

local im_size = { 16, 32 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local J = L.upsample(2, 1)(L.map(add_c)(I))
local K = L.map(add_c)(J)
local mod = L.lambda(K, I)

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
