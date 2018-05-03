local I = require 'betelgeuse.ir'
local skeleton = require 'betelgeuse.passes.skeleton'

return skeleton{
   apply = function(cur, input)
      if cur.m.kind == 'unzip' then
         if input.kind == 'apply' and input.m.kind == 'zip' then
            return input.v
         end
      elseif cur.m.kind == 'zip' then
         if input.kind == 'apply' and input.m.kind == 'unzip' then
            return input.v
         end
      end
   end
}
