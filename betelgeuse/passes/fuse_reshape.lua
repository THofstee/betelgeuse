local I = require 'betelgeuse.ir'
local skeleton = require 'betelgeuse.passes.skeleton'

return skeleton{
   apply = function(cur, input)
      if cur.m.kind == 'partition' then
         if input.kind == 'apply' and input.m.kind == 'flatten' then
            -- @todo: fix for case where counts do not match
            if cur.counts == input.size then
               return input.v
            end
         end
      end
   end
}
