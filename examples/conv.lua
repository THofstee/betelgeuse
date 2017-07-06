local L = require 'lang'
L.import()

-- convolution
local im_size = { 1920, 1080 }
local pad_size = { 1920+16, 1080+3 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(2, 1, 8, 8)(I)
local st = L.stencil(4, 4)(pad)
local taps = L.const(L.array2d(L.uint8(), 4, 4), {
						{  4, 14, 14,  4 },
						{ 14, 32, 32, 14 },
						{ 14, 32, 32, 14 },
						{  4, 14, 14,  4 }})
local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
local st_wt = L.zip_rec()(L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local m = conv(st_wt)
local m2 = L.map(L.reduce(L.add()))(L.map(L.map(L.mul()))(st_wt))
