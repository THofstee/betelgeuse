local L = require 'lang'
L.import()

-- add two image streams
local im_size = { 1920, 1080 }
local I = input(array2d(uint8(), im_size[1], im_size[2]))
local J = input(array2d(uint8(), im_size[1], im_size[2]))
local ij = zip_rec()(concat(I, J))
local m = map(add())(ij)
