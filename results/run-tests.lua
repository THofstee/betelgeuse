local inspect = require 'inspect'

local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'
G.render = false

local log = require 'log'
log.level = 'warn'

local mode = 'verilator'
local clean_after_test = false

local lfs = require 'lfs'
lfs.chdir('examples')

os.execute('make clean')

local examples = {
   -- 'updown',     -- upsample -> downsample
   -- 'box_filter', -- like a convolution but no weights
   'conv2',      -- convolution
   -- 'strided',    -- strided convolution
   -- 'twopass',    -- separable convolution
   -- 'unsharp',    -- unsharp mask
   -- 'harris',     -- harris corner detection
   --NYI 'depth',      -- depth from stereo
   --NYI 'histogram',  -- histogram
   -- 'flow',       -- lucas-kanade optical flow
   --NYI 'sift',       -- SIFT
   --NYI 'dnn',        -- single convlayer or mini-DNN (MNIST/CIFAR)
}

local results = {}

for _,example in ipairs(examples) do
   local filename = example .. '.lua'
   local mod = dofile(filename)

   results[example] = {}

   -- utilization
   local rates = {
      { 1, 32 },
      { 1, 16 },
      -- { 1,  8 },
      -- { 1,  4 },
      -- { 1,  2 },
      { 1,  1 },
      -- { 2,  1 },
      -- { 4,  1 },
      -- { 8,  1 },
   }


   for i,rate in ipairs(rates) do
      if clean_after_test then os.execute('make clean') end

      print(example, inspect(rate))

      local util = P.reduction_factor(mod, rate)
      local res = P.translate(mod)
      res = P.transform(res, util)
      res = P.streamify(res, rate)
      res = P.peephole(res)
      res = P.make_mem_happy(res)

      local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
      local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

      local filename = example .. '_' .. rate[1] .. '_' .. rate[2]

      local in_image
      if in_size[1] == 1920 and in_size[2] == 1080 then
         in_image = '1080p.raw'
      elseif in_size[1] == 32 and in_size[2] == 32 then
         in_image = 'box_32.raw'
      else
         assert(false, 'Unsupported input size')
      end

      R.harness{
         backend = mode,
         fn = res,
         inFile = in_image, inSize = in_size,
         outFile = filename, outSize = out_size,
         earlyOverride = 48000,
      }

      if mode == 'verilator' then
         local res = {}

         local f = assert(io.popen('make out/' .. filename .. '.verilator.bmp'))
         local s = assert(f:read('*a'))
         f:close()

         res.cycles = tonumber(string.match(s, 'Cycles: (%d+)'))

         results[example][rate] = res
      elseif mode == 'axi' then
         assert(false, 'axi test suite not yet supported')
      else
         assert(false, 'Unsupported mode')
      end
   end
end

lfs.chdir('../results/')

local pareto = require 'pareto'
pareto(results)

local serialize = require 'serialize'
print(serialize(results))

local f = assert(io.open('cycles.lua', 'w'))
f:write(inspect(results))
f:close()

local f = assert(io.open('cycles.txt', 'w'))
f:write(serialize(results))
f:close()
