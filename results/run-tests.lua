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

-- os.execute('make clean')

local examples = {
   -- 'updown',     -- upsample -> downsample
   'box_filter', -- like a convolution but no weights
   -- 'conv2',      -- convolution
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

local function write_results(results)
   local pareto = require 'pareto'
   pareto(results)

   local f = assert(io.open('cycles.lua', 'w'))
   f:write(inspect(results))
   f:close()

   local serialize = require 'serialize'
   local f = assert(io.open('cycles.txt', 'w'))
   f:write(serialize(results))
   f:close()

   local f = assert(io.popen('column -s, -t cycles.txt'))
   local s = assert(f:read('*l'))
   while true do
     print(s)
     local ns = f:read('*l')

     if not ns then
       break
     end

     if string.match(ns, "%a+") ~= string.match(s, "%a+") then
       print()
     end
     s = ns
   end
   f:close()
end

for _,example in ipairs(examples) do
   local filename = example .. '.lua'
   local mod = dofile(filename)

   results[example] = {}

   -- utilization
   local rates = {
      -- { 1, 32 },
      -- { 1, 16 },
      -- { 1,  8 },
      -- { 1,  4 },
      { 1,  2 },
      { 1,  1 },
      -- { 2,  1 },
      -- { 4,  1 },
      -- { 8,  1 },
   }

   for i,rate in ipairs(rates) do
      if clean_after_test then os.execute('make clean') end

      print(example, inspect(rate))

      local res = P.opt(mod, rate)
      local r,s = P.rigel(res)

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
         backend = 'metadata',
         fn = r,
         inFile = in_image, inSize = in_size,
         outFile = filename, outSize = out_size,
         earlyOverride = 48000000,
      }

      if mode ~= 'terra' then
         local backend = mode
         if mode == 'axi' then
            backend = 'verilator'
         end

         R.harness{
            backend = backend,
            fn = r,
            inFile = in_image, inSize = in_size,
            outFile = filename, outSize = out_size,
            earlyOverride = 48000000,
         }
      end

      local gold_file = tostring(in_size[2]) .. '-' .. example .. '.bmp'

      if mode == 'terra' then
         local res = {}

         local f = assert(io.popen('make out/' .. filename .. '.terra.bmp'))
         local s = assert(f:read('*a'))
         f:close()

         res.correct = os.execute('diff gold/' .. gold_file .. ' out/' .. filename .. '.terra.bmp') == 0

         results[example][rate] = res
      elseif mode == 'verilator' then
         local res = {}

         local f = assert(io.popen('make out/' .. filename .. '.verilator.bmp'))
         local s = assert(f:read('*a'))
         f:close()

         res.cycles = tonumber(string.match(s, 'Cycles: (%d+)'))

         res.correct = os.execute('diff gold/' .. gold_file .. ' out/' .. filename .. '.verilator.bmp') == 0

         results[example][rate] = res
      elseif mode == 'axi' then
         local res = {}

         local f = assert(io.popen('make out/' .. filename .. '.zynq20vivado.bmp'))
         local s = assert(f:read('*a'))
         f:close()

         -- get area
         -- local f = io.open('out/' .. filename .. '_zynq20vivado/utilization.txt')
         -- local s = f:read('*a')
         -- f:close()

         -- res.rams = string.match(s, "Block RAM Tile.-(%d+).-\n")
         -- res.area = string.match(s, "%| Slice.-(%d+).-\n")

         local f = io.open('out/' .. filename .. '_zynq20vivado/utilization_h.txt')
         local s = f:read('*a')
         f:close()

         local matchstr = "|%s*HarnessHSFN%s*|%s*(%w+)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*|%s*(%d+)%s*"
         local top, total_lut, logic_lut, lutram, srl, ff, ramb36, ramb18, dsp48 = s:match(matchstr)

         res.luts = total_lut
         res.ffs = ff
         res.rams = ramb36

         -- make sure we grabbed information about the right module in the hierarchy
         local metadata = dofile('out/' .. filename .. '.metadata.lua')
         assert(metadata.topModule == top)

         -- get cycles
         local f = io.open('out/' .. filename .. '.zynq20vivado.cycles.txt')
         local s = f:read('*a')
         f:close()

         res.cycles = string.match(s, "(%d+)")

         -- check for correctness
         res.correct = os.execute('diff gold/' .. gold_file .. ' out/' .. filename .. '.zynq20vivado.bmp') == 0

         results[example][rate] = res
      else
         assert(false, 'Unsupported mode')
      end

      -- save results after each run
      lfs.chdir('../results/')
      write_results(results)
      lfs.chdir('../examples')
   end
end
