local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'

local im_size = { 1920, 1080 }

local blury = L.const(L.array2d(L.fixed(9, 0), 1, 3), {
                      { 1 },
                      { 2 },
                      { 1 }})

local dx = L.const(L.array2d(L.fixed(9, 0), 3, 1), {
                      { 1, 0, -1 }})

local function conv(s, taps)
   local pad_size = im_size
   -- local pad_size = { im_size[1]+16, im_size[2]+3 }
   local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(s[1], s[2], s[3], s[4])(pad)
   local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
   local st_wt = L.zip_rec()(L.concat(st, wt))
   local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
   -- local conv = L.chain(conv, L.map(div256()), L.map(L.trunc(8)))
   local m = L.crop(0, 0, 0, 0)(conv(st_wt))
   -- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
   local mod = L.lambda(m, I)
   return mod
end

local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local x1 = conv({ -1, 0, 3, 1 }, dx)(I)
local x2 = conv({ 0, -1, 1, 3 }, blury)(x1)
local mod = L.lambda(x2, I)

local gv = require 'graphview'
gv(mod)
-- assert(false)

-- @todo: replace consts with
-- local STTYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )
-- local ITYPE = types.tuple{STTYPE,STTYPE:makeConst()}
-- inp = R.input( ITYPE )

-- utilization
local rates = {
   -- { 1, 32 },
   -- { 1, 16 },
   -- { 1,  8 },
   { 1,  4 },
   -- { 1,  2 },
   -- { 1,  1 },
   -- { 2,  1 },
   -- { 4,  1 },
   -- { 8,  1 },
}

local res = {}
for i,rate in ipairs(rates) do
   local util = P.reduction_factor(mod, rate)
   res[i] = P.translate(mod)
   res[i] = P.transform(res[i], util)
   res[i] = P.streamify(res[i], rate)
   res[i] = P.peephole(res[i])
end

gv(res[1])

local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

-- local R = require 'rigelSimple'
-- R.harness{
--    fn = res[1],
--    inFile = "1080p.raw", inSize = in_size,
--    outFile = "conv", outSize = out_size,
--    earlyOverride = 48000,
-- }

-- @todo: new harness
-- R.harness{
--    fn = hsfn,
--    outFile = "conv_wide_handshake_taps",
--    inFile="frame_128.raw",
--    tapType=STTYPE:makeConst(), tapValue=tapValue,
--    inSize={inputW,inputH},
--    outSize={inputW,inputH}
-- }

return mod
