local R = require 'rigelSimple'
local RM = require 'modules'
local C = require 'examplescommon'

local inspect = require 'inspect'

local to_handshake = require 'betelgeuse.passes.to_handshake'

local _VERBOSE = false

local function linenum(level)
   return debug.getinfo(level or 2, 'l').currentline
end

local function is_handshake(t)
   if t:isNamed() and t.generator == 'Handshake' then
      return true
   elseif t.kind == 'tuple' and is_handshake(t.list[1]) then
      return true
   end

   return false
end

local function base(m)
   local ignored = {
      apply = true,
      makeHandshake = true,
      liftHandshake = true,
      liftDecimate = true,
      waitOnInput = true,
   }

   if m.fn and ignored[m.kind] then
      return base(m.fn)
   else
      return m
   end
end

local function get_input(m)
   while m.inputs[1] do
      m = m.inputs[1]
   end
   return m
end

local function change_rate(input, out_size)
   local t = input.type
   if is_handshake(t) then
      t = t.params.A
   end

   local arr_t, w, h
   if t:isArray() then
      arr_t = t.over
      w = t.size[1]
      h = t.size[2]
   else
      arr_t = t
      w = 1
      h = 1
   end

   local in_cast = R.connect{
      input = input,
      toModule = R.HS(
         C.cast(
            R.array2d(arr_t, w, h),
            R.array2d(arr_t, w*h, 1)
         )
      )
   }

   local w_out = out_size[1]
   local h_out = out_size[2]

   local rate = R.connect{
      input = in_cast,
      toModule = R.HS(
         R.modules.changeRate{
            type = arr_t,
            H = 1,
            inW = w*h,
            outW = w_out*h_out
         }
      )
   }

   local output = R.connect{
      input = rate,
      toModule = R.HS(
         C.cast(
            R.array2d(arr_t, w_out*h_out, 1),
            R.array2d(arr_t, w_out, h_out)
         )
      )
   }

   return output
end

-- @todo: rename function
-- @todo: change to take in max_rate and util instead
local function divisor(n, k)
   -- find the smallest divisor of n greater than k
   for i=k,math.floor(math.sqrt(n)) do
      if n%i == 0 then
         return i
      end
   end

   -- find the greatest divisor of n smaller than k
   for i=k,2,-1 do
      if n%i == 0 then
         return i
      end
   end

   -- couldn't find anything better, return 1
   return 1
end

-- @todo: replace reduce_rate on modules to be reduce_rates on apply
local reduce_rate = {}
local reduce_rate_mt = {
   __call = function(reduce_rate, m, util)
      -- @todo: this should also make things spit out multiple parallel branches if trying to meet a certain utilization?
      if util[2] <= util[1] then return m end

      local dispatch = m.kind
      if string.find(dispatch, 'lift') then return reduce_rate.lift(m, util) end
      assert(reduce_rate[dispatch], "dispatch function " .. dispatch .. " is nil")
      return reduce_rate[dispatch](m, util)
   end
}
setmetatable(reduce_rate, reduce_rate_mt)

function reduce_rate.makeHandshake(m, util)
   if string.find(m.fn.fn.kind, 'lift') then return reduce_rate.lift(m, util) end
   return reduce_rate[m.fn.fn.kind](m, util)
end

function reduce_rate.liftHandshake(m, util)
   assert(false, "not yet implemented")
end

function reduce_rate.apply(m, util)
   -- return R.connect{
   --     input = reduce_rate(m.inputs[1]),
   --     toModule = reduce_rate(m)
   -- }
   if string.find(m.fn.kind, 'lift') then return reduce_rate.lift(m, util) end
   return reduce_rate[m.fn.kind](m, util)
end

function reduce_rate.input(m, util)
   if is_handshake(m.type) then
      return m
   else
      return R.input(R.HS(m.type))
   end
end

function reduce_rate.concat(m, util)
   for i,input in ipairs(m.inputs) do
      local in_type = base(input).outputType
      -- print(inspect(in_type, {depth = 2}))
   end

   local inputs = {}
   for i,input in ipairs(m.inputs) do
      inputs[i] = reduce_rate(input, util)
   end

   return R.concat(inputs)
end

local dont = false -- @todo: remove
function reduce_rate.map(m, util)
   local input
   if dont then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   local m = base(m.fn)
   local t = m.inputType
   local w = m.W
   local h = m.H

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local in_rate = change_rate(input, { par, 1 })

   if util[1]*(max_reduce/par)/util[2] < 1 and par ~= 1 then print('case of par>1 not yet implemented') end
   if util[1]*(max_reduce/par)/util[2] < 1 and par == 1 then
      -- we would still like to further reduce parallelism, reduce inner module
      local in_cast = R.connect{
         input = in_rate,
         toModule = R.HS(
            C.cast(
               R.array2d(input.type.params.A.over, par, 1),
               input.type.params.A.over
            )
         )
      }

      local inter = R.connect{
         input = in_cast,
         toModule = R.HS(m.fn)
      }

      if m.fn.kind == 'map' then
         -- @todo: runs into issues where the reduce_rate on the inner map starts calling reduce_rate on its inputs again........
         -- @todo: this is actually probably almost the wanted behavior, we push down the new utilization through the pipeline and need to adjust certain inputs, right? for example, constSeq that is an input to this module should be reduced from [16,1][1,1] to [8,1][1,1], etc.
         -- @todo: wouldn't have this issue if reduce_rate.map was operating on modules instead of applys
         -- @todo: maybe still can be on applys, but then internally theres a reduce_rate that operates on the modules, and then the outer function that works on applys still inlines everything? this way i can still keep the weird concat -> packtuple -> soatoaos thing in its own function instead of reduce_rate.apply
         dont = true
         local m2 = reduce_rate(inter, { util[1], math.floor(util[2]/max_reduce) })

         -- @todo: commented out lines meant for par > 1, where we still need outer map but operating over a rate reduced inner module
         -- m = R.modules.map{
         --		fn = base(m2.fn),
         --		size = { par }
         -- }

         -- local inter = R.connect{
         --		input = in_rate,
         --		toModule = R.HS(m)
         -- }
         -- dont = false

         -- return change_rate(inter, { w, h })
         local out_cast = R.connect{
            input = m2,
            toModule = R.HS(
               C.cast(
                  m2.type.params.A,
                  R.array2d(m2.type.params.A, par, 1)
               )
            )
         }

         dont = false
         return change_rate(out_cast, { w, h })
      end

      local out_cast = R.connect{
         input = inter,
         toModule = R.HS(
            C.cast(
               inter.type.params.A,
               R.array2d(inter.type.params.A, par, 1)
            )
         )
      }

      return change_rate(out_cast, { w, h })
   else
      m = R.modules.map{
         fn = m.fn,
         size = { par }
      }

      local inter = R.connect{
         input = in_rate,
         toModule = R.HS(m)
      }

      return change_rate(inter, { w, h })
   end
   -- @todo: the module being mapped over probably also needs to be optimized, for example recursive maps
end

function reduce_rate.SoAtoAoS(m, util)
   print('@todo: implement', m.kind, linenum())
   local input = reduce_rate(m.inputs[1], util)

   local m = m.fn
   local t = m.inputType

   if input.kind == 'apply' and input.fn.kind == 'packTuple' and input.inputs[1].kind == 'concat' then
      local size = m.outputType.params.A.size

      local max_reduce = size[1]*size[2]
      local par = math.ceil(max_reduce * util[1]/util[2])
      par = divisor(max_reduce, par)

      local streams_in = {}
      local hack = {}
      local hack2 = {}

      -- [4,4][32,32] -> [4,4][1,1] -> [1,1]

      for i,inpt in ipairs(input.inputs[1].inputs) do
         streams_in[i] = change_rate(inpt, { par, 1 })
         hack[i] = streams_in[i].type.params.A
         hack2[i] = hack[i].over
      end

      local inter = R.connect{
         input = R.concat(streams_in),
         toModule = RM.packTuple(hack)
      }

      local inter2 = R.connect{
         input = inter,
         toModule = R.HS(
            R.modules.SoAtoAoS{
               type = hack2,
               size = { par, 1 }
            }
         )
      }

      return change_rate(inter2, size)
   end

   return R.connect{
      input = input,
      toModule = R.HS(m)
   }
end

function reduce_rate.broadcast(m, util)
   -- @todo: broken for inputs with par > 1
   local input = reduce_rate(m.inputs[1], util)
   local m = base(m.fn)

   local out_size = m.outputType.size

   local max_reduce = out_size[1]*out_size[2]
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local in_cast = R.connect{
      input = input,
      toModule = R.HS(C.broadcast(m.inputType, par, 1))
   }

   local inter = R.connect{
      input = in_cast,
      toModule = R.HS(
         R.modules.upsampleSeq{
            type = m.inputType,
            V = par,
            size = { m.inputType.width, m.inputType.height },
            scale = { out_size[1]*out_size[2], 1 }
         }
      )
   }

   return change_rate(inter, out_size)
end

function reduce_rate.lift(m, util)
   -- certain modules need to be reduced, but are implemented as lifts
   if base(m.fn).generator == 'C.broadcast' then
      return reduce_rate.broadcast(m, util)
   end

   -- otherwise, don't do anything
   return R.connect{
      input = reduce_rate(m.inputs[1], util),
      toModule = R.HS(m.fn)
   }
end

function reduce_rate.pad(m, util)
   local input = reduce_rate(m.inputs[1], util)
   local m = base(m.fn)

   local t = m.inputType
   local w = m.width
   local h = m.height
   local out_size = m.outputType.size

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local in_rate = change_rate(input, { par, 1 })

   local m = R.modules.padSeq{
      type = m.type,
      V = par,
      size = { w, h },
      pad = { m.L, m.R, m.Top, m.B },
      value = m.value
   }

   local inter = R.connect{
      input = in_rate,
      toModule = R.HS(m)
   }

   return change_rate(inter, out_size)
end

function reduce_rate.crop(m, util)
   local input = reduce_rate(m.inputs[1], util)

   -- @todo: double check implementation
   local m = base(m.fn)

   local t = m.inputType
   local w = m.width
   local h = m.height
   local out_size = m.outputType.size

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local in_rate = change_rate(input, { par, 1 })

   m = R.modules.cropSeq{
      type = m.type,
      V = par,
      size = { w, h },
      crop = { m.L, m.R, m.Top, m.B }
   }

   local inter = R.connect{
      input = in_rate,
      toModule = R.HS(m)
   }

   return change_rate(inter, out_size)
end

function reduce_rate.upsample(m, util)
   -- @todo: change to be upsampleY first then upsampleX, once implemented
   local input = reduce_rate(m.inputs[1], util)
   local m = base(m.fn)

   -- @todo: divide by util to figure out output element type
   -- @todo: sample for downsample
   local out_size = m.outputType.size
   local par = math.ceil(out_size[1]*out_size[2] * util[1]/util[2])
   local in_size = { m.inputType.size[1], m.inputType.size[2] }

   -- @todo: reduce in x first or in y first?
   -- @todo: hack
   in_size[2] = math.ceil(in_size[2]/util[2])
   in_size[1] = math.ceil(in_size[1]/(util[2]/(m.inputType.size[2]/in_size[2])))
   if par ~= 1 then in_size = { par, 1 } end

   local in_rate = change_rate(input, in_size)

   -- @todo: this is not scanline order anymore really
   m = R.modules.upsampleSeq{
      type = m.type,
      V = par,
      size = { m.width, m.height },
      scale = { m.scaleX, m.scaleY }
   }

   local inter = R.connect{
      input = in_rate,
      toModule = R.HS(m)
   }

   return change_rate(inter, out_size)
end

function reduce_rate.downsample(m, util)
   local input = reduce_rate(m.inputs[1], util)
   local m = base(m.fn)

   local in_size = m.inputType.size
   local par = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local in_rate = change_rate(input, { par, 1 })

   local out_size = m.outputType.size

   if m.scaleY == 1 then
      m = RM.downsampleXSeq(
         m.type,
         m.width,
         m.height,
         par,
         m.scaleX
      )
   else
      -- @todo: for some reason this is super slow when scaleY == 1
      m = R.modules.downsampleSeq{
         type = m.type,
         V = par,
         size = { m.width, m.height },
         scale = { m.scaleX, m.scaleY }
      }
   end

   local inter = R.connect{
      input = in_rate,
      toModule = R.HS(m)
   }

   return change_rate(inter, out_size)
end

function reduce_rate.stencil(m, util)
   print('@todo: fixme', m.kind, linenum())
   local input = reduce_rate(m.inputs[1], util)

   local m = base(m.fn)

   -- @todo: hack, should move this to translate probably
   -- @todo: total hack, needs extra pad and crop
   m.xmin = m.xmin - m.xmax
   m.xmax = 0
   m.ymin = m.ymin - m.ymax
   m.ymax = 0

   local size = { m.w, m.h }

   local par = math.ceil(size[1]*size[2] * util[1]/util[2])
   par = divisor(m.w, par)

   if util[1]*(size[1]*size[2]/par)/util[2] < 1 and par == 1 then
      local m = R.modules.linebuffer{
         type = m.inputType.over,
         V = par,
         size = size,
         stencil = { m.xmin, m.xmax, m.ymin, m.ymax }
      }

      -- assert(false, '@todo: implement the columnLinebuffer thing')
      -- local m = R.modules.columnLinebuffer{
      --     type = m.inputType.over,
      --     V = par,
      --     size = size,
      --     stencil = m.ymin
      -- }

      local in_rate = change_rate(input, { par, 1 })

      local inter = R.connect{
         input = in_rate,
         toModule = R.HS(m)
      }

      return change_rate(inter, size)
   else
      local m = R.modules.linebuffer{
         type = m.inputType.over,
         V = par,
         size = size,
         stencil = { m.xmin, m.xmax, m.ymin, m.ymax }
      }

      local in_rate = change_rate(input, { par, 1 })

      local inter = R.connect{
         input = in_rate,
         toModule = R.HS(m)
      }

      return change_rate(inter, size)
   end
end

function reduce_rate.packTuple(m, util)
   local input = reduce_rate(m.inputs[1], util)

   local m = base(m.fn)

   local hack = {}
   for i,t in ipairs(m.inputType.list) do
      hack[i] = t.params.A
   end

   return R.connect{
      input = input,
      toModule = RM.packTuple(hack)
   }
end

function reduce_rate.lambda(m, util)
   assert(false, "Not yet implemented")
   -- @todo: recurse optimization calls here?
   local m = R.HS(m)

   local input = R.input(m.inputType)

   local output = R.connect{
      input = input,
      toModule = m
   }

   return R.defineModule{
      input = input,
      output = output
   }
end

function reduce_rate.constSeq(m, util)
   print('@todo: implement', m.kind, linenum())

   return m
end

-- @todo: maybe this should only take in a lambda as input
local function transform(m, util)
   local m = to_handshake(m)
   local output
   if m.kind == 'lambda' then
      output = m.output
   else
      output = m
   end

   -- run rate optimization
   output = reduce_rate(output, util)

   if m.kind == 'lambda' then
      return R.defineModule{
         input = get_input(output),
         output = output
      }
   else
      return output
   end
end

if _VERBOSE then
   for k,v in pairs(reduce_rate) do
      reduce_rate[k] = function(m, util)
         print('reduce_rate.' .. k)
         return v(m, util)
      end
   end
end

return transform
