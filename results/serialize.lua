local function serialize(results)
   -- format all results and add to a table
   local s = {}
   local n = 1
   for prog, data in pairs(results) do
      for rate, perf in pairs(data) do
         s[n] = {
            prog,
            rate[1], rate[2],
            perf.cycles or 0,
            perf.area or 0
         }
         n = n+1
      end
   end

   -- sort the table first by name, then by rate
   local function f(a, b)
      if a[1] == b[1] then
         return a[2]/a[3] < b[2]/b[3]
      else
         return a[1] < b[1]
      end
   end

   table.sort(s, f)

   -- return string
   local s = ''
   s = s .. 'examples,rate,cycles,area' .. '\n'
   for _, v in ipairs(s) do
      s = s .. v[1] .. ','                -- example
      s = s .. v[2] .. '/' .. v[3] .. ',' -- rate
      s = s .. v[4] .. ','                -- cycles
      s = s .. v[5] .. '\n'               -- area
   end
end

return serialize
