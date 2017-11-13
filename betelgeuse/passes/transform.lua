local R = require 'rigelSimple'
local RM = require 'modules'
local C = require 'examplescommon'

local memoize = require 'memoize'
local inspect = require 'inspect'
local log = require 'log'

local to_handshake = require 'betelgeuse.passes.to_handshake'

local _VERBOSE = true
local DONT = false

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
   __call = memoize(function(reduce_rate, m, util)
      -- @todo: this should also make things spit out multiple parallel branches if trying to meet a certain utilization?
      if util[2] <= util[1] then return m end

      local dispatch = m.kind
      if string.find(dispatch, 'lift') then return reduce_rate.lift(m, util) end
      assert(reduce_rate[dispatch], "dispatch function " .. dispatch .. " is nil")
      return reduce_rate[dispatch](m, util)
   end)
}
setmetatable(reduce_rate, reduce_rate_mt)

function reduce_rate.makeHandshake(m, util)
   if string.find(m.fn.fn.kind, 'lift') then return reduce_rate.lift(m, util) end
   if reduce_rate[m.fn.fn.kind] == nil then
      log.fatal('reduce_rate.' .. m.fn.fn.kind .. ' not defined.')
   end
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
      -- log.trace(inspect(in_type, {depth = 2}))
   end

   local inputs = {}
   for i,input in ipairs(m.inputs) do
      inputs[i] = reduce_rate(input, util)
   end

   return R.concat(inputs)
end

-- function reduce_rate.concat(m, util)
--    for i,input in ipairs(m.inputs) do
--       local in_type = base(input).outputType
--       -- log.trace(inspect(in_type, {depth = 2}))
--    end

--    -- local inputs = {}
--    -- for i,input in ipairs(m.inputs) do
--    --    inputs[i] = reduce_rate(input, util)
--    --    inputs[i] = R.fifo{
--    --       input = inputs[i],
--    --       depth = 128,
--    --    }
--    --    -- R.connect{
--    --    --    input = inputs[i],
--    --    --    toModule =
--    -- end

--    return R.concat(inputs)
-- end

function reduce_rate.reduce(m, util)
   local input
   if DONT then
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

   local reduce_fn = m.fn
   if reduce_fn.kind == 'lambda' then
      reduce_fn = reduce_fn.output.fn
   end

   if par ~= 1 then
      -- smaller reduce_par
      local inter = R.connect{
         input = in_rate,
         toModule = R.HS(
            R.modules.reduce{
               fn = reduce_fn,
               size = { par, 1 }
            }
         )
      }

      -- followed by reduce_seq
      return R.connect{
         input = inter,
         toModule = R.HS(
            R.modules.reduceSeq{
               V = max_reduce/par,
               fn = reduce_fn,
            }
         )
      }
   else
      -- just reduce_seq
      return R.connect{
         input = in_rate,
         toModule = R.HS(
            R.modules.reduceSeq{
               V = max_reduce/par,
               fn = reduce_fn,
            }
         )
      }
   end
end


function reduce_rate.map(m, util)
   local input
   if DONT then
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

   if util[1]*(max_reduce/par)/util[2] < 1 and par ~= 1 then
      log.warn('case of par>1 not yet implemented')
   elseif util[1]*(max_reduce/par)/util[2] < 1 and par == 1 then
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

      if not DONT then
         -- @todo: runs into issues where the reduce_rate on the inner map starts calling reduce_rate on its inputs again........
         -- @todo: this is actually probably almost the wanted behavior, we push down the new utilization through the pipeline and need to adjust certain inputs, right? for example, constSeq that is an input to this module should be reduced from [16,1][1,1] to [8,1][1,1], etc.
         -- @todo: wouldn't have this issue if reduce_rate.map was operating on modules instead of applys
         -- @todo: maybe still can be on applys, but then internally theres a reduce_rate that operates on the modules, and then the outer function that works on applys still inlines everything? this way i can still keep the weird concat -> packtuple -> soatoaos thing in its own function instead of reduce_rate.apply

         -- @todo: this might not be needed
         DONT = true

         -- @todo: I dont think this should be calling reduce_rate?
         -- @todo: reduce_rate should really probably just take in modules...
         -- @todo: this is the current rationale: reduce_rate needs to take in an apply.
         --        since it takes in an apply, if we want to reduce the rate of the func
         --        we are mapping with, then we need to pass it the inputs as well.
         --        we've already called reduce_rate on the inputs above, so now what will
         --        happen is as we reduce_rate on the module, it will call reduce_rate on
         --        the inputs as well. in theory, we've maximally reduced the inputs so
         --        this should just be a no-op and those parts should just return the
         --        existing piece. this either means that this shouldn't call reduce_rate,
         --        reduce_rate shouldn't work on the inputs unless its an apply, or that
         --        the don't flag is not needed.
         log.trace('reducing inner module of a map')
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
         -- DONT = false

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

         DONT = false
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
   log.warn('@todo: implement')
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

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
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end
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
            size = { m.inputType.size[1], m.inputType.size[2] },
            scale = { out_size[1]*out_size[2], 1 }
         }
      )
   }

   return change_rate(inter, out_size)
end

function reduce_rate.lift(m, util)
   local what = base(m.fn).generator or base(m.fn).kind
   log.trace('[reduce_rate.lift] ' .. what)

   -- certain modules need to be reduced, but are implemented as lifts
   if base(m.fn).generator == 'C.broadcast' then
      return reduce_rate.broadcast(m, util)
   end

   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   -- otherwise, don't do anything
   return R.connect{
      input = input,
      toModule = R.HS(m.fn)
   }
end

function reduce_rate.pad(m, util)
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end
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
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

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
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end
   local m = base(m.fn)

   local in_size = m.inputType.size
   local par_in = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local out_size = m.outputType.size
   local par_out = math.ceil(out_size[1]*out_size[2] * util[1]/util[2] / par_in)

   local in_rate = change_rate(input, { par_in, 1 })

   if par_in ~= par_out then
      log.warn('@todo: this probably is not implemented correctly.')
      m = R.HS(C.broadcast(m.type, par_out, 1))
   --    -- m = R.modules.upsample{
   --    --    type = m.type,
   --    --    size = { 1, 1 },
   --    --    scale = { m.scaleX, m.scaleY },
   --    -- }
   else
      m = R.modules.upsampleSeq{
         type = m.type,
         V = par_in,
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

function reduce_rate.downsample(m, util)
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end
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

local STP = require 'StackTracePlus'

function reduce_rate.SSR(m, util)
   log.warn('passthrough')
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   local m = base(m.fn)

   return R.connect{
      input = input,
      toModule = R.HS(m)
   }
end

function reduce_rate.unpackStencil(m, util)
   log.warn('passthrough')
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   local m = base(m.fn)

   return R.connect{
      input = input,
      toModule = R.HS(m)
   }
end

function reduce_rate.stencil(m, util)
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   local m = base(m.fn)

   -- @todo: hack, should move this to translate probably
   -- @todo: total hack, needs extra pad and crop
   log.warn('@todo: fixme')
   m.xmin = m.xmin - m.xmax
   m.xmax = 0
   m.ymin = m.ymin - m.ymax
   m.ymax = 0

   local size = { m.w, m.h }

   local par = math.ceil(size[1]*size[2] * util[1]/util[2])
   par = divisor(m.w, par)

   log.debug(m.w, m.h)
   log.debug(par)
   log.debug(util[1], util[2])

   local in_size = { m.w, m.h }
   local st_size = { m.xmax - m.xmin + 1, m.ymax - m.ymin + 1} -- stencil size
   local par_outer = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])
   local temp = (par_outer*util[2]) / (in_size[1]*size[2])
   local par_inner = math.ceil(st_size[1]*st_size[2] / temp)

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

   log.debug('par_outer: ' .. inspect(par_outer))
   log.debug('par_inner: ' .. inspect(par_inner))

   if par_outer == 1 then
      -- a reduced rate stencil should be a linebuffer that feeds into a changerate
      -- e.g. linebuffer creates uint[4,4] -> changeRate creates uint[1,1]
      -- since we need the output type of the stencil to match the boundary type specified
      -- before, this means we would create something like this:
      -- linebuffer -> seralize -> vectorize
      -- where the seralize and the vectorize end up cancelling out.
      -- this means that the changeRate needs to come from the module that takes the
      -- linebuffer output as input
      inter = R.connect{
         input = inter,
         toModule = R.HS(
            C.cast(
               base(inter.fn).outputType,
               base(inter.fn).outputType.over
            )
         )
      }

      inter = change_rate(inter, { par_inner, 1 })
      inter = change_rate(inter, st_size)

      inter = R.connect{
         input = inter,
         toModule = R.HS(
            C.cast(
               base(inter.fn).outputType,
               R.array2d(base(inter.fn).outputType, 1, 1)
            )
         )
      }

      -- wait a minute...
   end

   return change_rate(inter, size)
end

function reduce_rate.packTuple(m, util)
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

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

-- @todo: split body in to inline_cur and then use inline_cur in other places?
local function inline_hs(m, input)
   return m.output:visitEach(function(cur, inputs)
         if cur.kind == 'input' then
            return input
         elseif cur.kind == 'apply' then
            return R.connect{
               input = inputs[1],
               toModule = R.HS(cur.fn)
            }
         elseif cur.kind == 'concat' then
            local hack = {}
            for i,inpt in ipairs(inputs) do
               hack[i] = inpt.type.params.A
            end

            return R.connect{
               input = R.concat(inputs),
               toModule = RM.packTuple(hack)
            }
         elseif cur.kind == 'constant' then
            local inter = R.connect{
               input = nil,
               toModule = R.HS(
                  R.modules.constSeq{
                     type = R.array2d(cur.type, 1, 1),
                     P = 1,
                     value = { cur.value }
                  }
               )
            }

            return R.connect{
               input = inter,
               toModule = R.HS(
                  C.cast(
                     R.array2d(cur.type, 1, 1),
                     cur.type
                  )
               )
            }
         else
            assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
         end
   end)
end

function reduce_rate.constant(m, util)
   return R.HS(
      R.modules.constSeq{
         type = R.array2d(m.type, 1, 1),
         P = 1,
         value = { m.value }
      }
   )
end

function reduce_rate.linebuffer(m, util)
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   local m = base(m.fn)

   return R.connect{
      input = input,
      toModule = R.HS(m)
   }
end

function reduce_rate.lambda(m, util)
   -- -- log.error('this should not have been called')
   -- local input
   -- if DONT then
   --    input = m.inputs[1]
   -- else
   --    input = reduce_rate(m.inputs[1], util)
   -- end

   -- local m = base(m.fn)

   -- return R.connect{
   --    input = input,
   --    toModule = R.HS(m)
   -- }
   -- -- return m

   -- the only time that this function should be called (hopefully) is
   -- when we have a map(lambda). in this case, the map has fully reduced
   -- its parallelism to [1,1], and we want to reduce further with the lambda.
   -- this means it should be okay to just inline the module here, and then
   -- call reduce_rate again on the inlined module to actually perform the
   -- reduction.

   -- @todo: what about reduce(lambda)? does this just become lambda -> reduceSeq?
   local input = m.inputs[1] -- reduce_rate(m.inputs[1], util)

   local m = inline_hs(base(m), input)

   return reduce_rate(m, util)

   -- -- assert(false, "Not yet implemented")
   -- -- @todo: recurse optimization calls here?
   -- -- @todo: can i just inline the lambda?
   -- -- log.trace(inspect(m, {depth = 2}))

   -- local m = base(m)

   -- local i = get_input(m.output)
   -- log.trace(m.kind)
   -- log.trace(inspect(i, {depth = 2}))

   -- local input = R.input(m.inputType)

   -- local output = inline(m, input)

   -- local res = R.defineModule{
   --    input = input,
   --    output = output
   -- }

   -- log.trace(inspect(res, {depth = 2}))

   -- return res
end

function reduce_rate.constSeq(m, util)
   local out_t = base(m.fn).outputType
   local vals = base(m.fn).value

   -- unwrap outer arrays of 1
   while out_t.kind == 'array' do
      if out_t.size[1]*out_t.size[2] == 1 then
         out_t = out_t.over
         vals = vals[1]
      else
         break
      end
   end

   -- if we only had an array of 1 then too bad
   if out_t.kind ~= 'array' then
      log.debug('could not reduce constSeq further')
      return m
   end

   local len = #vals
   local par = math.ceil(len * util[1]/util[2])

   local stream = R.connect{
      input = nil,
      toModule = R.HS(
         R.modules.constSeq{
            type = R.array2d(base(m.fn).outputType.over.over, len, 1),
            P = par/len,
            value = base(m.fn).value[1],
         }
      )
   }

   return change_rate(stream, out_t.size)
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
         log.trace('reduce_rate.' .. k ..
                      '(..., ' .. '{ ' .. util[1] .. ' , ' .. util[2] .. ' }' .. ')')
         return v(m, util)
      end
   end
end

return transform
