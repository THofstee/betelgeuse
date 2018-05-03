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

      if util[1]/util[2] ~= 1 then
         local r = util[2]/util[1]
         local new_h = math.ceil(input.type.h/r)
         r = math.ceil(r/(input.type.h/new_h))
         local new_w = math.ceil(input.type.w/r)
         r = math.ceil(r/(input.type.w/new_w))
         inputs[i] = IR.apply(IR.partition({ new_w, new_h }), inputs[i])
      end
   end

   local res = IR.concat(unpack(inputs))

   if res.type ~= m.type then
      res = IR.apply(IR.zip(), res)
      res = IR.apply(IR.map_t(IR.zip(), { 1, 1 }), res)
      res = IR.apply(IR.flatten({ 1, 2 }), res)
      res = IR.apply(IR.unzip(), res)
   end

   return res
end

function reduce_rate.select(m, util)
   return IR.select(reduce_rate(m.v, util), m.n)
end

function reduce_rate.reduce_x(m, util)
   local w = m.size[1]
   local h = m.size[2]

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   -- @todo: should it be w first then h or h then w?
   local new_w = w/math.ceil(w/par)
   par = par/new_w
   local new_h = h/math.ceil(h/par)
   par = par/new_h

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ new_w, new_h }), input)

   local out_w = in_rate.type.w
   local out_h = in_rate.type.h
   local inter = IR.apply(IR.map_t(IR.reduce_x(m.m, { new_w, new_h }), { out_w, out_h }), in_rate)
   local inter2 = IR.apply(IR.reduce_t(m.m, { out_w, out_h }), inter)

   return IR.lambda(inter2, input)
end

function reduce_rate.map_x(m, util)
   local w = m.size[1]
   local h = m.size[2]

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   -- @todo: double check usage of new_w and new_h vs par here
   local r = util[2]/util[1]
   local new_h = math.ceil(h/r)
   r = r / (h/new_h)
   local new_w = math.ceil(w/r)
   r = r / (w/new_w)

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ new_w, new_h }), input)

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
      local inter = IR.apply(IR.map_t(a, { new_w, new_h}), in_rate)
      local out_rate = IR.apply(IR.flatten({ new_w, new_h}), inter)
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
         m = IR.map_x(m.m, { new_w, new_h })
      end

      local inter = IR.apply(IR.map_t(m, { par, 1 }), in_rate)
      local out_rate = IR.apply(IR.flatten({ par, 1}), inter)
      return IR.lambda(out_rate, input)
   end
end

function reduce_rate.zip(m, util)
   return m
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

function reduce_rate.pad_x(m, util)
   local in_size = { m.type_in.w, m.type_in.h }
   local par = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ par, 1 }), input)

   local new_m = IR.pad_t(m.left, m.right, m.top, m.bottom)
   local inter = IR.apply(new_m, in_rate)

   local out_rate = IR.apply(IR.flatten({ par, 1 }), inter)

   return IR.lambda(out_rate, input)
end

function reduce_rate.crop_x(m, util)
   local in_size = { m.type_in.w, m.type_in.h }
   local par = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local input = IR.input(m.type_in)
   local in_rate = IR.apply(IR.partition({ par, 1 }), input)

   local new_m = IR.crop_t(m.left, m.right, m.top, m.bottom)
   local inter = IR.apply(new_m, in_rate)

   local out_rate = IR.apply(IR.flatten({ par, 1 }), inter)

   return IR.lambda(out_rate, input)
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

function reduce_rate.stencil_x(m, util)
   -- @todo: needs to handle reducing to stencil_t
   local in_size = { m.type_in.w, m.type_in.h }
   local max_reduce = in_size[1]*in_size[2]
   local par = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])

   local remain = util[1]*util[2] * (par / (in_size[1]*in_size[2]))
   if remain == 1 then
      local input = IR.input(m.type_in)
      local in_rate = IR.apply(IR.partition({ par, 1 }), input)

      local new_m = IR.stencil_x(m.offset_x, m.offset_y, m.extent_x, m.extent_y)
      local inter = IR.apply(IR.map_t(new_m, in_size), in_rate)

      local out_rate = IR.apply(IR.flatten({ par, 1 }), inter)

      return IR.lambda(out_rate, input)
   else
      local input = IR.input(m.type_in)
      local in_rate = IR.apply(IR.partition({ par, 1 }), input)

      local new_m = IR.stencil_t(m.offset_x, m.offset_y, m.extent_x, m.extent_y)
      local inter = IR.apply(IR.map_t(new_m, in_size), in_rate)

      local out_rate = IR.apply(IR.flatten({ par, 1 }), inter)

      return IR.lambda(out_rate, input)
   end
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
