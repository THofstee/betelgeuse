local I = require 'betelgeuse.ir'

local function inline(m, input)
   local function helper(cur)
      if not cur then return nil end

      if cur.kind == 'input' then
         return input
      elseif cur.kind == 'apply' then
         return I.apply(cur.m, helper(cur.v))
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

   return helper(m.f)
end

return inline
