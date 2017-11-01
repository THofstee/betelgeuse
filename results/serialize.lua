local function serialize(results)
   -- format all results and add to a table
   local t = {}
   local n = 1
   for prog, data in pairs(results) do
      for rate, perf in pairs(data) do
         t[n] = {
            example = prog,
            rate = rate,
            cycles = perf.cycles or 0,
            area = perf.area or 0
         }
         n = n+1
      end
   end

   -- sort the table first by name, then by rate
   local function f(a, b)
      if a.example == b.example then
        return a.rate[1]/a.rate[2] < b.rate[1]/b.rate[2]
      else
         return a.example < b.example
      end
   end

   table.sort(t, f)

   -- reformat table
   local t2 = {}
   local i = 0
   local example = nil
   for _,v in ipairs(t) do
      if example ~= v.example then
         example = v.example
         i = i+1
         t2[i] = { example = v.example, tests = {} }
      end

      if v.rate[1] * v.rate[2] == 1 then
         t2[i].base_cycles = v.cycles
         t2[i].base_area = v.area
      end
      table.insert(t2[i].tests, v)
   end

   -- return string
   local s = ''
   s = s .. 'examples' .. ','
   s = s .. 'rate' .. ','
   s = s .. 'cycles' .. ','
   s = s .. 'perf relative 1/1' .. ','
   s = s .. 'area' .. ','
   s = s .. 'area relative 1/1' .. ','
   s = s .. 'correct' .. '\n'

   for _,example in ipairs(t2) do
      for _,test in ipairs(example.tests) do
         s = s .. test.example .. ','
         s = s .. test.rate[1] .. '/' .. test.rate[2] .. ','
         s = s .. test.cycles .. ','
         s = s .. test.cycles / example.base_cycles .. ','
         s = s .. test.area .. ','
         s = s .. test.area / example.base_area .. ','
         s = s .. 'false' .. '\n' -- @todo: check correctness
      end
   end

   return s
end

return serialize
