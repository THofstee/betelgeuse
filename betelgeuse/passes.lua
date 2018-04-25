--- A set of compilation passes to lower to and optimize Rigel.
-- @module passes
local path_set = false
if not path_set then
   package.path = "./rigel/?.lua;./rigel/src/?.lua;./rigel/examples/?.lua;" .. package.path
   path_set = true
end

-- Disable SDF checking in rigel for now
local rigel = require 'rigel'
rigel.SDF = false

local R = require 'rigelSimple'
local RM = require 'modules'
local C = require 'examplescommon'
local rtypes = require 'types'
local L = require 'betelgeuse.lang'

-- @todo: remove this after debugging
local inspect = require 'inspect'
local log = require 'log'

local function linenum(level)
   return debug.getinfo(level or 2, 'l').currentline
end

local P = {}

P.transform = require 'betelgeuse.passes.transform'
P.translate = require 'betelgeuse.passes.translate'
P.to_handshake = require 'betelgeuse.passes.to_handshake'
P.json = require 'betelgeuse.passes.json'
P.fuse_reshape = require 'betelgeuse.passes.fuse_reshape'
P.fuse_map = require 'betelgeuse.passes.fuse_map'
P.fuse_concat = require 'betelgeuse.passes.fuse_concat'
P.peephole = require 'betelgeuse.passes.peephole'
P.rigel = require 'betelgeuse.passes.rigel'

function P.opt(mod, rate)
   local util = P.reduction_factor(mod, rate)

   local res
   res = P.translate(mod)
   res = P.transform(res, util)
   res = P.fuse_reshape(res)
   res = P.fuse_map(res)
   res = P.peephole(res)
   res = P.fuse_concat(res)

   return res
end

local _VERBOSE = false

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
P.base = base

-- @todo: should make this a class method in lang
function reduction_factor(m, in_rate)
   local factor = { in_rate[1], in_rate[2] }

   local function process(t)
      if t.kind == 'array2d' then
         process(t.t)
         factor[2] = factor[2] * t.w * t.h
      end
   end

   process(L.unwrap(m).x.type)

   local scale = math.min(factor[1], factor[2])
   factor = { factor[1]/scale, factor[2]/scale }

   return factor
end
P.reduction_factor = reduction_factor

local function get_input(m)
   while m.inputs[1] do
      m = m.inputs[1]
   end
   return m
end
P.get_input = get_input

local function get_name(m)
   if false then
      return base(m).kind .. '-' .. base(m).name
   end

   if m.kind == 'lambda' then
      return m.kind .. '(' .. get_name(m.output) .. ')'
   elseif m.name then
      if m.fn then
         return m.kind .. '_' .. m.name .. '(' .. get_name(m.fn) .. ')'
      elseif m.kind == 'input' then
         return m.kind .. '_' .. m.name .. '(' .. tostring(m.type) .. ')'
      else
         return m.name
      end
   else
      if m.fn then
         return m.kind .. '(' .. get_name(m.fn) .. ')'
      elseif m.kind == 'input' then
         return m.kind .. '(' .. tostring(m.type) .. ')'
      else
         return m.kind
      end
   end
end
P.get_name = get_name

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
P.change_rate = change_rate

-- @todo: split body in to inline_cur and then use inline_cur in other places?
local function inline(m, input)
   return m.output:visitEach(function(cur, inputs)
         if cur.kind == 'input' then
            return input
         elseif cur.kind == 'apply' then
            return R.connect{
               input = inputs[1],
               toModule = cur.fn
            }
         elseif cur.kind == 'concat' then
            return R.concat(inputs)
         elseif cur.kind == 'applyMethod' then
            log.trace(cur.fnname)
            return cur
         else
            assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
         end
   end)
end

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
         else
            assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
         end
   end)
end

-- @todo: maybe this should operate the same way as transform and peephole and case on whether or not the input is a lambda? in any case i think all 3 should be consistent.
-- @todo: do i want to represent this in my higher level language instead as an internal feature (possibly useful too for users) and then translate to rigel instead?
-- converts a module to operate on streams instead of full images
local function streamify(m, elem_rate)
   -- elem rate := { n_pixels, every_m_cycles }
   local elem_rate = elem_rate or { 1, 1 }
   local elem_size = elem_rate[1]
   local elem_rate = { 1, elem_rate[2] }

   local t_in, w_in, h_in
   if is_handshake(m.inputType) then
      if m.inputType.params.A.kind ~= 'array' then return m end
      t_in = m.inputType.params.A.over
      w_in = m.inputType.params.A.size[1]
      h_in = m.inputType.params.A.size[2]
   else
      if m.inputType.kind ~= 'array' then return m end
      t_in = m.inputType.over
      w_in = m.inputType.size[1]
      h_in = m.inputType.size[2]
   end

   local t_out, w_out, h_out
   if is_handshake(m.outputType) then
      t_out = m.outputType.params.A.over
      w_out = m.outputType.params.A.size[1]
      h_out = m.outputType.params.A.size[2]
   else
      t_out = m.outputType.over
      w_out = m.outputType.size[1]
      h_out = m.outputType.size[2]
   end

   local stream_in = R.input(R.HS(R.array(t_in, elem_size)), {elem_rate})

   local vec_in = change_rate(stream_in, { w_in, h_in })

   local vec_out = inline(P.to_handshake(m), vec_in)

   local stream_out = change_rate(vec_out, { elem_size, 1 })

   return R.defineModule{
      input = stream_in,
      output = stream_out
   }
end
P.streamify = streamify

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
   for i in k,2,-1 do
      if n%i == 0 then
         return i
      end
   end

   -- couldn't find anything better, return 1
   return 1
end

local function get_type_signature(cur)
   if cur.kind == 'input' or cur.kind == 'constant' then
      return 'nil' .. ' -> ' .. tostring(cur.type)
   elseif cur.kind == 'concat' then
      local input = '{'
      for i,t in ipairs(cur.inputs) do
         input = input .. tostring(t.type) .. ', '
      end
      input = string.sub(input, 1, -3) .. '}'
      return input .. ' -> ' .. tostring(cur.type)
   else
      if tostring(cur.fn.inputType) == 'null' then
         return 'nil' .. ' -> ' .. tostring(cur.fn.outputType)
      else
         return tostring(cur.fn.inputType) .. ' -> ' .. tostring(cur.fn.outputType)
      end
   end
end
P.get_type_signature = get_type_signature

local function needs_hs(m)
   local modules = {
      changeRate = true,
   }

   return modules[m.kind]
end

local function handshakes(m)
   -- @todo: this function shouldn't crash if it can't remove HS, it should just return the original pipeline. need to add another case in cur.kind i think

   -- Remove handshakes on everything as we iterate
   local function removal(cur, inputs)
      if cur.kind == 'apply' then
         if needs_hs(base(cur)) then
            -- If something needs a handshake, discard the changes
            return cur
         elseif inputs[1].type.generator == 'Handshake' then
            -- Something earlier failed, so don't remove handshake here
            return R.connect{
               input = inputs[1],
               toModule = cur.fn
            }
         else
            -- Our input isn't handshaked, so remove handshake if we need to
            if cur.fn.kind == 'makeHandshake' then
               return R.connect{
                  input = inputs[1],
                  toModule = cur.fn.fn
               }
            end

            return R.connect{
               input = inputs[1],
               toModule = cur.fn
            }
         end
      elseif cur.kind == 'input' then
         -- Start by removing handshake on all inputs
         if cur.type.generator == 'Handshake' then
            return R.input(cur.type.params.A)
         end
      end
      return cur
   end

   if m.kind == 'lambda' then
      local output = m.output:visitEach(removal)
      local input = get_input(output)

      return R.defineModule{
         input = input,
         output = output
      }
   else
      local output = m:visitEach(removal)
      return output
   end

   return
end
P.handshakes = handshakes

function P.import()
   local reserved = {
      import = true,
      debug = true,
   }

   for name, fun in pairs(P) do
      if not reserved[name] then
         rawset(_G, name, fun)
      end
   end
end

return P
