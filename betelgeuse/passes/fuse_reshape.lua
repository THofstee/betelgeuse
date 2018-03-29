local I = require 'betelgeuse.ir'
local inspect = require 'inspect'

local function merge(cur, input)
   if cur.m.kind == 'partition' then
      if input.kind == 'apply' and input.m.kind == 'flatten' then
         -- @todo: fix for case where counts do not match
         if cur.counts == input.size then
            return input.v
         end
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
