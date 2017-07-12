local L = require 'lang'
L.import()

-- convolution
local im_size = { 1920, 1080 }
local pad_size = { 1920+16, 1080+3 }
local I = input(array2d(uint8(), im_size[1], im_size[2]))
local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local taps = const(array2d(uint8(), 4, 4), {
					  {  4, 14, 14,  4 },
					  { 14, 32, 32, 14 },
					  { 14, 32, 32, 14 },
					  {  4, 14, 14,  4 }})
local wt = broadcast(pad_size[1], pad_size[2])(taps)
print(st.type)
print(wt.type)
local st_wt = zip_rec()(concat(st, wt))
local conv = chain(map(map(mul())), map(reduce(add())))
local m = conv(st_wt)
local m2 = map(reduce(add()))(map(map(mul()))(st_wt))
