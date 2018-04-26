local I = require 'betelgeuse.ir'
local inspect = require 'inspect'
local inline = require 'betelgeuse.passes.inline'
local memoize = require 'memoize'

local function merge(cur, input)
   if cur.m.kind == 'map_t' then
      if input.kind == 'apply' and input.m.kind == 'map_t' then
         local lambda_in = I.input(input.m.m.type_in)

         local lambda_out
         if input.m.m.kind == 'lambda' then
            lambda_out = inline(input.m.m, lambda_in)
         else
            lambda_out = I.apply(input.m.m, lambda_in)
         end
         lambda_out = I.apply(cur.m.m, lambda_out)

         local lambda = I.lambda(lambda_out, lambda_in)

         return I.apply(I.map_t(lambda, cur.m.size), input.v)
      end
   end

   -- @todo: should this be here, or should it be something like return nil and this happens on the outside?
   return I.apply(cur.m, input)
end

local function skeleton(m)
   local input = m.x

   local function helper(cur)
      if not cur then return nil end

      if cur.kind == 'input' then
         return input
      elseif cur.kind == 'apply' then
         local input = helper(cur.v)

         local function helper2(cur)
            if cur.kind == 'lambda' then
               return skeleton(cur)
            elseif cur.kind == 'map_t' or cur.kind == 'map_x' then
               return I[cur.kind](helper2(cur.m), cur.size)
            elseif cur.kind == 'reduce_t' or cur.kind == 'reduce_x' then
               return I[cur.kind](helper2(cur.m), cur.size)
            else
               return cur
            end
         end

         if cur.m.kind == 'map_t' or cur.m.kind == 'map_x' then
            cur.m = helper2(cur.m)
         elseif cur.m.kind == 'reduce_t' or cur.m.kind == 'reduce_x' then
            cur.m = helper2(cur.m)
         end

         return merge(cur, input)
      elseif cur.kind == 'concat' then
         local inputs = {}
         for i,v in ipairs(cur.vs) do
            inputs[i] = helper(v)
         end
         return I.concat(unpack(inputs))
      elseif cur.kind == 'select' then
         return I.select(helper(cur.v), cur.n)
      elseif cur.kind == 'const' then
         return cur
      else
         assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
      end
   end

   return I.lambda(helper(m.f), m.x)
end
skeleton = memoize(skeleton)

return skeleton
