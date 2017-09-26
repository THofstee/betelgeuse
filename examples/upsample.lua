local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'

-- map -> upsample -> map
local x = L.input(L.fixed(9, 0))
local add_c = L.lambda(L.add()(L.concat(x, L.const(L.fixed(9, 0), 30))), x)

local im_size = { 2, 4 }
local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local J = L.upsample(2, 1)(L.map(add_c)(I))
local K = L.map(add_c)(J)
local mod = L.lambda(K, I)

-- utilization
local elem_rate = { 1, 1 }
local util = P.reduction_factor(mod, elem_rate)

-- passes
local res
res = P.translate(mod)
print('--- Translate ---')
P.rates(res)
res = P.transform(res, util)
print('--- Transform ---')
P.rates(res)
res = P.streamify(res, elem_rate)
print('--- Streamify ---')
P.rates(res)
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)
-- res = P.handshakes(res)
-- print('--- Handshake ---')
-- P.rates(res)
