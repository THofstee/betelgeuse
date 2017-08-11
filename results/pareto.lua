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

local data = {
   { 33177639, 1876 },
   { 33177639, 1876 },
   { 16588838, 1884 },
   {  8294437, 1961 },
   {  4147237, 2047 },
   {  2073636, 1857 },
   {  1036837, 1862 },
   {   518442, 2321 },
   {   259263, 3680 },
}

local frontier, others = pareto(data)

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

flot.render(p, name)
