local I = require 'betelgeuse.ir'
local inspect = require 'inspect'
local inline = require 'betelgeuse.passes.inline'

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

local function fuse(m)
   local input = m.x

   local function helper(cur)
      if not cur then return nil end

      if cur.kind == 'input' then
         return input
      elseif cur.kind == 'apply' then
         local input = helper(cur.v)
         return merge(cur, input)
      elseif cur.kind == 'concat' then
         local inputs = {}
         for i,v in ipairs(cur.vs) do
            inputs[i] = helper(v)
         end
         return I.concat(unpack(inputs))
      elseif cur.kind == 'select' then
         return I.select(helper(cur.v), cur.n)
      elseif cur.kind == 'constant' then
         return cur
      else
         assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
      end
   end

   return I.lambda(helper(m.f), m.x)
end

return fuse
