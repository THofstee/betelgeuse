local L = require 'lang'
local P = require 'passes'

-- convolution
local im_size = { 16, 32 }
local pad_size = { im_size[1]+16, im_size[2]+3 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local taps = L.const(L.array2d(L.uint8(), 4, 4), {
						{  4, 14, 14,  4 },
						{ 14, 32, 32, 14 },
						{ 14, 32, 32, 14 },
						{  4, 14, 14,  4 }})
local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
local st_wt = L.zip_rec()(L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local m = L.crop(8, 8, 2, 1)(conv(st_wt))
local mod = L.lambda(m, I)

-- passes
local res
res = P.translate(mod)
res = P.to_handshake(res)
res = P.transform(res)
-- res = P.streamify(res) -- @todo: this is broken
res = P.peephole(res)
print('--- Peephole ---')
P.rates(res)
