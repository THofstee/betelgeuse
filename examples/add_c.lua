local inspect = require 'inspect'
local L = require 'lang'
local P = require 'passes'
local R = require 'rigelSimple'

local get_name = P.get_name
local transform = P.transform
local changeRate = P.change_rate
local peephole = P.peephole
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
   local I = L.input(L.array2d(L.uint8(), size[1], size[2]))
   local x = L.input(L.uint8())
   local c = L.const(L.uint8(), const_val)
   local add_c = L.lambda(L.add()(L.concat(x, c)), x)
   local m_add = L.map(add_c)
   -- return L.lambda(m_add(I), I)
   return L.lambda(L.chain(m_add, m_add)(I), I)
end
local im_size = { 32, 16 }
local m = create_module(im_size)

-- write_file('box_out.raw', m(read_file('box_32_16.raw')))

local x = L.input(L.uint8())
local c = L.const(L.uint8(), const_val)
local add_c = L.lambda(L.add()(L.concat(x, c)), x)
local r2 = translate(add_c(x))
local r3 = translate(add_c)
local r4 = P.streamify(translate(add_c))
-- R.harness{ fn = R.HS(translate(m)),
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-0translate", outSize = im_size }

local out = translate(m)
print("--- After Translate ---")
P.rates(out)
local stream_out = P.streamify(translate(m))
print("--- After Streamify ---")
P.rates(stream_out)
-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-1streamify", outSize = im_size }

local stream_out = transform(stream_out)
print("--- After Transform ---")
P.rates(stream_out)
-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-2transform", outSize = im_size }

local stream_out = peephole(stream_out)
print("--- After Peephole ---")
P.rates(stream_out)
-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test-3peephole", outSize = im_size }

local stream_out = P.handshakes(stream_out)
print("--- After Handshake Optimization ---")
P.rates(stream_out)
-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test", outSize = im_size }
