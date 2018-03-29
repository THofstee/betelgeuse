local I = require 'betelgeuse.ir'
local inspect = require 'inspect'
local memoize = require 'memoize'
local inline = require 'betelgeuse.passes.inline'

local function fuse(m)
   local input = m.x

   local function helper(cur)
      if not cur then return nil end

      if cur.kind == 'input' then
         return input
      elseif cur.kind == 'apply' then
         local input = helper(cur.v)

         local function helper2(cur)
            print(cur.kind)
            if cur.kind == 'lambda' then
               return fuse(cur)
            elseif cur.kind == 'map_t' or cur.kind == 'map_x' then
               return I[cur.kind](helper2(cur.m), cur.size)
            else
               assert(false, cur.kind)
            end
         end

         if cur.m.kind == 'map_t' or cur.m.kind == 'map_x' then
            cur.m = helper2(cur.m)
         end

         return I.apply(cur.m, input)
      elseif cur.kind == 'concat' then
         local inputs = {}
         for i,v in ipairs(cur.vs) do
            inputs[i] = helper(v)
         end
         return I.concat(unpack(inputs))
      elseif cur.kind == 'select' then
         local input = helper(cur.v)
         assert(input.kind == 'concat')
         return input.vs[cur.n]
      elseif cur.kind == 'const' then
         return cur
      else
         assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
      end
   end

   return I.lambda(helper(m.f), m.x)
end
fuse = memoize(fuse)

return fuse
