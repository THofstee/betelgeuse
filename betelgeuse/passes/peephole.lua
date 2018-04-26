local I = require 'betelgeuse.ir'
local inspect = require 'inspect'
local memoize = require 'memoize'
local inline = require 'betelgeuse.passes.inline'

local function peephole(cur, input)
   if cur.m.kind == 'shift' then
      if cur.m.n == 0 then
         return input
      end
   elseif cur.m.kind == 'trunc' then
      if type_out == type_in then
         return input
      end
   end

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

         return peephole(cur, input)
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
