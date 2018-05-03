local I = require 'betelgeuse.ir'
local memoize = require 'memoize'

local function is_higher_level(kind)
   local index = {
      ['map_x'] = true,
      ['map_t'] = true,
      ['reduce_x'] = true,
      ['reduce_t'] = true,
   }

   return index[kind]
end

local function entry(override)
   local function skeleton(m)
      local input = m.x

      local function helper(cur)
         if not cur then return nil end

         if cur.kind == 'input' then
            if override.input then
               return override.input(cur) or input
            end

            return input
         elseif cur.kind == 'apply' then
            local input = helper(cur.v)

            local function helper2(cur)
               if cur.kind == 'lambda' then
                  return skeleton(cur)
               elseif is_higher_level(cur.kind) then
                  return I[cur.kind](helper2(cur.m), cur.size)
               else
                  return cur
               end
            end

            if is_higher_level(cur.m.kind) then
               cur.m = helper2(cur.m)
            end

            if override.apply then
               return override.apply(cur, input) or I.apply(cur.m, input)
            end

            return I.apply(cur.m, input)
         elseif cur.kind == 'concat' then
            local inputs = {}
            for i,v in ipairs(cur.vs) do
               inputs[i] = helper(v)
            end

            if override.concat then
               return override.concat(cur, inputs) or I.concat(unpack(inputs))
            end

            return I.concat(unpack(inputs))
         elseif cur.kind == 'select' then
            local input = helper(cur.v)

            if override.select then
               return override.select(cur, input) or I.select(input, cur.n)
            end

            return I.select(input, cur.n)
         elseif cur.kind == 'const' then
            if override.const then
               return override.const(cur) or cur
            end

            return cur
         else
            assert(false, 'skeleton ' .. cur.kind .. ' not yet implemented')
         end
      end

      local res = I.lambda(helper(m.f), m.x)

      if override.lambda then
         return override.lambda(res) or res
      end

      return res
   end
   skeleton = memoize(skeleton)

   return skeleton
end

return entry
