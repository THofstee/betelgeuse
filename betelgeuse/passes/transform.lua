local IR = require 'betelgeuse.ir'
local memoize = require 'memoize'
local inspect = require 'inspect'
local log = require 'log'

local _VERBOSE = false

local function linenum(level)
   return debug.getinfo(level or 2, 'l').currentline
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

-- local function match_interface(m, type_in, type_out)
--    print(type_in, type_out)
--    local input = IR.input(type_in)

--    print(m)

--    return IR.lambda(output, input)
-- end

local function get_input(m)
   -- while m.inputs[1] do
   --    m = m.inputs[1]
   -- end

   -- return m

   if not m then
      return nil
   end

   if m.kind == 'input' then
      return m
   end

   return get_input(m.inputs[1]) or get_input(m.inputs[2])
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

function reduce_rate.apply(a, util)
   local m = reduce_rate(a.m, util)
   local v = reduce_rate(a.v, util)

   if m.kind == 'lambda' then
      local function inline(m, input)
         local function helper(cur)
            if not cur then return nil end

            if cur.kind == 'input' then
               return input
            elseif cur.kind == 'apply' then
               return IR.apply(cur.m, helper(cur.v))
            elseif cur.kind == 'concat' then
               local inputs = {}
               for i,v in ipairs(cur.vs) do
                  inputs[i] = helper(v)
               end
               return IR.concat(unpack(inputs))
            elseif cur.kind == 'select' then
               return IR.select(helper(cur.v), cur.n)
            elseif cur.kind == 'constant' then
               return cur
            else
               assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
            end
         end

         return helper(m.f)
      end

      return inline(m, v)
   else
      return IR.apply(m, v)
   end
end

function reduce_rate.input(m, util)
   return m
end

function reduce_rate.concat(m, util)
   local inputs = {}
   for i,input in ipairs(m.vs) do
      inputs[i] = reduce_rate(input, util)
   end

   return IR.concat(unpack(inputs))
end

function reduce_rate.select(m, util)
   return IR.select(reduce_rate(m.v, util), m.n)
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

function reduce_rate.map_x(m, util)
   print(inspect(m.size))
   local w = m.size[1]
   local h = m.size[2]

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ par, 1 }), input)

   -- @todo: effective_rate is the wrong name for this variable. what it really is describing is a notification that "we have exhausted the parallelism available to us in this module, and we would like to reduce the rate even further". For example if par is 1, then max_reduce/par = max_reduce. If we want to reduce to less than the equivalent of 1/max_reduce, then this value will be less than 1.
   -- @todo: the above provides a rather compelling argument to normalize util to 1 w.r.t. some term. e.g. {2, 4} becomes {1, 2}, {8, 1} stays as {8, 1}
   local effective_rate = util[1]*(max_reduce/par)/util[2]
   if effective_rate < 1 and par ~= 1 then
      log.warn('case of par>1 not yet implemented')
   elseif effective_rate < 1 and par == 1 then
      -- print(inspect(m, {depth = 2}))
      local newm = reduce_rate(m.m, { util[1], math.floor(util[2]/max_reduce) })
      -- print(inspect(newm, {depth = 2}))
      log.warn('not sure if this is doing the right thing...')
      local a = IR.map_t(newm, m.size)
      local inter = IR.apply(IR.map_t(a, { par, 1}), in_rate)
      local out_rate = IR.apply(IR.flatten({ par, 1}), inter)
      return IR.lambda(out_rate, input)

      -- -- we would still like to further reduce parallelism, reduce inner module
      -- local in_cast = R.connect{
      --    input = in_rate,
      --    toModule = R.HS(
      --       C.cast(
      --          R.array2d(input.type.params.A.over, par, 1),
      --          input.type.params.A.over
      --       )
      --    )
      -- }

      -- local inter = R.connect{
      --    input = in_cast,
      --    toModule = R.HS(m.fn)
      -- }

      -- log.trace('reducing inner module of a map')
      -- local m2 = reduce_rate(inter, { util[1], math.floor(util[2]/max_reduce) })
      -- local out_cast = R.connect{
      --    input = m2,
      --    toModule = R.HS(
      --       C.cast(
      --          m2.type.params.A,
      --          R.array2d(m2.type.params.A, par, 1)
      --       )
      --    )
      -- }
   else
      if par == 1 then
         m = IR.map_t(m.m, { par, 1 })
      else
         m = IR.map_x(m.m, { par, 1 })
      end

      local inter = IR.apply(IR.map_t(m, { par, 1 }), in_rate)
      local out_rate = IR.apply(IR.flatten({ par, 1}), inter)
      return IR.lambda(out_rate, input)
   end
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

function reduce_rate.buffer(m, util)
   local input
   if DONT then
      input = m.inputs[1]
   else
      input = reduce_rate(m.inputs[1], util)
   end

   -- return input
   local m = base(m.fn)

   local out_size = m.outputType.size

   local max_reduce = out_size[1]*out_size[2]
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local in_rate = change_rate(input, { par, 1 })

   local inter = R.connect{
      input = in_rate,
      toModule = C.fifo(in_rate.type.params.A, m.depth)
   }

   local res = change_rate(inter, out_size)

   assert(res.type == input.type, "buffer input type and output type should match")
   return res
end

function reduce_rate.lift(m, util)
   local what = base(m.fn).generator or base(m.fn).kind
   log.trace('[reduce_rate.lift] ' .. what)

   -- certain modules need to be reduced, but are implemented as lifts
   if base(m.fn).generator == 'C.broadcast' then
      return reduce_rate.broadcast(m, util)
   elseif base(m.fn).generator == 'buffer' then
      return reduce_rate.buffer(m, util)
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

function reduce_rate.const(m, util)
   return m
end

function reduce_rate.add(m, util)
   return m
end

function reduce_rate.shift(m, util)
   return m
end

function reduce_rate.trunc(m, util)
   return m
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

function reduce_rate.upsample_x(m, util)
   local in_size = { m.type_in.w, m.type_in.h }
   local par_in = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local out_size = { m.type_out.w, m.type_out.h }
   local par_out = math.ceil(out_size[1]*out_size[2] * util[1]/util[2])
   -- @todo: check this, should it be the above or the commented out line below?
   -- local par_out = math.ceil(out_size[1]*out_size[2] * util[1]/util[2] / par_in)

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ par_in, 1 }), input)

   -- @todo: replace upsample_t with upsample_x(size, throughput=1)
   -- m = IR.upsample_x(m.x, m.y, par_out/par_in)
   if par_in ~= par_out then
      log.warn(string.format('@todo: double check this, par_in = %s, par_out = %s', par_in, par_out))

      m = IR.upsample_x(m.x, m.y)
   else
      local cyc = (m.x*m.y)*(par_out/par_in)
      log.warn(string.format('@todo: double check this, par_in = %s, par_out = %s, cyc = %s', par_in, par_out, cyc))
      m = IR.upsample_t(m.x, m.y, cyc)
   end
   local inter = IR.apply(IR.map_t(m, { par_out, 1 }), in_rate)

   -- @todo: double check if this should be par_out or par_in
   local out_rate = IR.apply(IR.flatten({ par_out, 1 }), inter)

   return IR.lambda(out_rate, input)
end

function reduce_rate.downsample_x(m, util)
   local in_size = { m.type_in.w, m.type_in.h }
   local par_in = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local out_size = { m.type_out.w, m.type_out.h }
   local par_out = math.ceil(out_size[1]*out_size[2] * util[1]/util[2] / par_in)

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ par_in, 1 }), input)

   local out_size = { m.type_out.w, m.type_out.h }

   if par_in ~= par_out then
      m = IR.downsample_x(m.x, m.y)
   else
      local cyc = (m.x*m.y)*par_out/par_in
      log.warn(string.format('@todo: double check this, par_in = %s, par_out = %s, cyc = %s, in_size = %s, out_size = %s', par_in, par_out, cyc, inspect(in_size), inspect(out_size)))
      m = IR.downsample_t(m.x, m.y, cyc)
   end
   local inter = IR.apply(IR.map_t(m, { par_out, 1 }), in_rate)

   local out_rate = IR.apply(IR.flatten({ par_out, 1 }), inter)
   return IR.lambda(out_rate, input)
end

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

   return R.connect{
      input = input,
      toModule = RM.packTuple(m.inputType.params.list)
   }
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
   return IR.lambda(reduce_rate(m.f, util), m.x)
   -- local input = m.x

   -- local m = inline(m.f, input)

   -- return reduce_rate(m, util)

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
   local output
   if m.kind == 'lambda' then
      output = m.f
   else
      output = m
   end

   -- run rate optimization
   output = reduce_rate(output, util)

   if m.kind == 'lambda' then
      -- @todo: the input should stay consistent so I think this works, but check
      return IR.lambda(output, m.x)
      -- return IR.lambda(output, get_input(output))
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
