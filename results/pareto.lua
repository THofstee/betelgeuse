local function pareto(data)
   local function unique(t)
      local res = {}
      local seen = {}

      for _,v in ipairs(t) do
         local old = seen
         local saw = false
         for _,n in ipairs(v) do
            if not seen[n] then
               seen[n] = {}
               saw = false
            else
               saw = true
            end
            seen = seen[n]
         end
         seen = old

         -- saw takes the value of the last element in the list being found in cache
         if not saw then
            table.insert(res, v)
         end
      end

      return res
   end

   local function cmp(a, b)
      if a[1] == a[b] then
         return a[2] < b[2]
      else
         return a[1] < b[1]
      end
   end

   data = unique(data)
   table.sort(data, cmp)

   local frontier = { data[1] }
   local min = data[1][2]

   for _,v in ipairs(data) do
      if v[2] < min then
         table.insert(frontier, v)
         min = v[2]
      end
   end

   local function deepcompare(t1,t2,ignore_mt)
      local ty1 = type(t1)
      local ty2 = type(t2)
      if ty1 ~= ty2 then return false end
      -- non-table types can be directly compared
      if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
      -- as well as tables which have the metamethod __eq
      local mt = getmetatable(t1)
      if not ignore_mt and mt and mt.__eq then return t1 == t2 end
      for k1,v1 in pairs(t1) do
         local v2 = t2[k1]
         if v2 == nil or not deepcompare(v1,v2) then return false end
      end
      for k2,v2 in pairs(t2) do
         local v1 = t1[k2]
         if v1 == nil or not deepcompare(v1,v2) then return false end
      end
      return true
   end

   local others = {}
   for _,v in ipairs(data) do
      local found = false
      for _,w in ipairs(frontier) do
         if deepcompare(v, w) then
            found = true
         end
      end
      if not found then table.insert(others, v) end
   end

   return frontier, others
end

-- takes filename as command line arg and then parses file

local name = arg[1]

local dir = 'graphs/'

local function gen_graphs(results)
   for prog, data in pairs(results) do
      local formatted_data = {}
      local n = 1
      for rate, perf in pairs(data) do
         formatted_data[n] = { perf.area or 0, perf.cycles or 0 }
         n = n+1
      end

      local frontier, others = pareto(formatted_data)

      local flot = require 'flot'

      local p = flot.Plot {
         legend = { position = 'se' },
      }

      -- in theory, could set hoverable to true and then add functionality to listen for hover events...
      p:add_series('other designs', others, {
                      color = 'red',
                      shadowSize = 0,
                      points = {
                         show = true
                      },
      })

      p:add_series('pareto optimal', frontier, {
                      color = 'green',
                      shadowSize = 0,
                      points = {
                         show = true
                      },
                      lines = {
                         show=true
                      },
      })

      flot.render(p, dir .. prog)
   end
end

local results = {
  box_filter = {
    [{ 1, 4 }] = {
      cycles = 1041
    },
    [{ 1, 1 }] = {
      cycles = 1041
    },
    [{ 1, 8 }] = {
      cycles = 1041
    },
    [{ 1, 16 }] = {
      cycles = 1041
    },
    [{ 1, 32 }] = {
      cycles = 1041
    },
    [{ 1, 2 }] = {
      cycles = 1041
    }
  },
  conv = {
    [{ 1, 4 }] = {
      cycles = 4115
    },
    [{ 1, 16 }] = {
      cycles = 16403
    },
    [{ 1, 32 }] = {
      cycles = 16403
    },
    [{ 1, 1 }] = {
      cycles = 1042
    },
    [{ 1, 2 }] = {
      cycles = 2067
    },
    [{ 1, 8 }] = {
      cycles = 8211
    }
  },
  harris = {
    [{ 1, 4 }] = {
      cycles = 1056
    },
    [{ 1, 16 }] = {
      cycles = 1056
    },
    [{ 1, 2 }] = {
      cycles = 1056
    },
    [{ 1, 1 }] = {
      cycles = 1056
    },
    [{ 1, 32 }] = {
      cycles = 1056
    },
    [{ 1, 8 }] = {
      cycles = 1056
    }
  },
  strided = {
    [{ 1, 32 }] = {
      cycles = 1635
    },
    [{ 1, 2 }] = {
      cycles = 1635
    },
    [{ 1, 16 }] = {
      cycles = 1635
    },
    [{ 1, 8 }] = {
      cycles = 1635
    },
    [{ 1, 4 }] = {
      cycles = 1635
    },
    [{ 1, 1 }] = {
      cycles = 1635
    }
  },
  twopass = {
    [{ 1, 8 }] = {
      cycles = 3100
    },
    [{ 1, 1 }] = {
      cycles = 1048
    },
    [{ 1, 16 }] = {
      cycles = 3100
    },
    [{ 1, 32 }] = {
      cycles = 3100
    },
    [{ 1, 4 }] = {
      cycles = 3100
    },
    [{ 1, 2 }] = {
      cycles = 3100
    }
  },
  unsharp = {
    [{ 1, 32 }] = {
      cycles = 16405
    },
    [{ 1, 1 }] = {},
    [{ 1, 4 }] = {
      cycles = 4117
    },
    [{ 1, 8 }] = {
      cycles = 8213
    },
    [{ 1, 16 }] = {
      cycles = 16405
    },
    [{ 1, 2 }] = {}
  },
  updown = {
    [{ 1, 4 }] = {
      cycles = 2056
    },
    [{ 1, 16 }] = {
      cycles = 2056
    },
    [{ 1, 2 }] = {
      cycles = 2056
    },
    [{ 1, 1 }] = {
      cycles = 1032
    },
    [{ 1, 32 }] = {
      cycles = 2056
    },
    [{ 1, 8 }] = {
      cycles = 2056
    }
  }
}

gen_graphs(results)

return gen_graphs
