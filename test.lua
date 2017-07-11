local inspect = require 'inspect'
local L = require 'lang'
--[[
   tests with rigel
--]]
local P = require 'passes'
local translate = P.translate

-- add constant to image (broadcast)
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local c = L.const(L.uint8(), 1)
local bc = L.broadcast(im_size[1], im_size[2])(c)
local m = L.map(L.add())(L.zip_rec()(L.concat(I, bc)))

-- add constant to image (lambda)
local im_size = { 32, 16 }
local const_val = 30
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local x = L.input(L.uint8())
local c = L.const(L.uint8(), const_val)
local add_c = L.lambda(L.add()(L.concat(x, c)), x)
local m_add = L.map(add_c)

-- could sort of metaprogram the thing like this, and postpone generation of the module until later
-- you could create a different function that would take in something like a filename and then generate these properties in the function and pass it in to the module generation
local function create_module(size)
   local const_val = 30
   local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
   local x = L.input(L.uint8())
   local c = L.const(L.uint8(), const_val)
   local add_c = L.lambda(L.add()(L.concat(x, c)), x)
   local m_add = L.map(add_c)
   -- return L.lambda(m_add(I), I)
   return L.lambda(L.chain(m_add, m_add)(I), I)
end
local m = create_module(im_size)

-- write_file('box_out.raw', m(read_file('box_32_16.raw')))

local R = require 'rigelSimple'

local streamify = P.streamify
local get_name = P.get_name
local transform = P.transform
local changeRate = P.change_rate
local peephole = P.peephole

-- @todo: add something like betel(function(I) map(f)(I) end) that will let you declare lambdas more easily
-- @todo: add something like an extra class that when called will lower the module into rigel and give you back something
-- @todo: remove the rigel harness calls, or make a nicer way to do that
-- @todo: add some sort of support for cross-module optimizations

-- local x = L.input(L.uint8())
local c = L.const(L.uint8(), const_val)
local add_c = L.lambda(L.add()(L.concat(x, c)), x)
local r2 = translate(add_c(x))
local r3 = translate(add_c)
local r4 = streamify(translate(add_c))
-- R.harness{ fn = R.HS(translate(m)),
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-0translate", outSize = im_size }

local out = translate(m)
print("--- After Translate ---")
out.output:visitEach(function(cur)
	  print(get_name(cur))
	  print(inspect(cur:calcSdfRate(out.output)))
end)


local stream_out = streamify(translate(m))
print("--- After Streamify ---")
stream_out.output:visitEach(function(cur)
	  print(get_name(cur))
	  print(inspect(cur:calcSdfRate(stream_out.output)))
end)

-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-1streamify", outSize = im_size }

local stream_out = transform(stream_out)
print("--- After Transform ---")
stream_out.output:visitEach(function(cur)
	  print(get_name(cur))
	  print(inspect(cur:calcSdfRate(stream_out.output)))
end)

-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-2transform", outSize = im_size }

local stream_out = peephole(stream_out)
print("--- After Peephole ---")
stream_out.output:visitEach(function(cur)
	  print(get_name(cur))
	  print(inspect(cur:calcSdfRate(stream_out.output)))
end)
-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-3peephole", outSize = im_size }

local stream_out = P.handshakes(stream_out)
print("--- After Handshake Optimization ---")
stream_out.output:visitEach(function(cur)
	  print(get_name(cur))
	  print(inspect(cur:calcSdfRate(stream_out.output)))
end)
P.debug(stream_out)
R.harness{ fn = stream_out,
           inFile = "box_32_16.raw", inSize = im_size,
           outFile = "test", outSize = im_size }

local r_m = translate(m)
-- R.harness{ fn = R.HS(r_m),
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test", outSize = im_size }

-- unpack = table.unpack

-- add two image streams
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local J = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local ij = L.zip_rec()(L.concat(I, J))
local m = L.map(L.add())(ij)

-- convolution
local im_size = { 640, 480 }
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
local m = conv(st_wt)
local m2 = L.map(L.reduce(L.add()))(L.map(L.map(L.mul()))(st_wt))
local mod = L.lambda(m2, I)

-- local res = translate(mod)

-- @todo: lucas-kanade
-- @todo: histogram
