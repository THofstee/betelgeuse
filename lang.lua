local inspect = require 'inspect'

-- @todo: fix type representation

local lang = {}

local function uint32()
   return { type = 'uint32', kind = 'type' }
end
lang.uint32 = uint32

local function array(t, n)
   return { array = { n = n, type = t }, type = 'array', kind = 'type' }
end
lang.array = array

local function array2d(t, w, h)
   return { array2d = { w = w, h = h, type = t }, type = 'array2d', kind = 'type' }
end
lang.array2d = array2d

local function print_type(t)
   local function print_helper(t)
	  if t.kind == 'type' then
		 if type(t.type) == 'table' then
			print_helper(t.type)
		 elseif t[t.type] ~= nil then
			io.write(t.type .. '<')
			print_helper(t[t.type].type)
			io.write('>')
		 else
			io.write(t.type)
		 end
	  elseif t.kind == 'func' then
		 io.write(t.func .. ' :: ')
		 print_helper(t.type_in)
		 io.write(' -> ')
		 print_helper(t.type_out)
	  end
   end

   print_helper(t)
   io.write('\n')
end

-- local function print_type(t)
--    local function print_helper(t)
-- 	  if type(t.type) == 'table' then
-- 		 print_helper(t.type)
-- 	  elseif t[t.type] ~= nil then
-- 		 io.write(t.type .. '<')
-- 		 print_helper(t[t.type].type)
-- 		 io.write('>')
-- 	  else
-- 		 io.write(t.type)
-- 	  end
--    end

--    print_helper(t)
--    io.write('\n')
-- end

local function broadcast()
   local f = {}

   f.type = function(d)
	  return array2d(d.type, d.w, d.h)
   end
   
   f.func = 'broadcast'
   f.kind = 'func'
   return f
end

local function stencil()
   local f = {}

   f.type = function(d)
	  return array2d(array2d(d.I.array2d.type, d.w, d.h), d.I.array2d.w, d.I.array2d.h)
   end
   
   f.func = 'stencil'
   f.kind = 'func'
   return f
end

-- @todo: rerwite apply to use ... and arg?
local function apply(f, d)
   local I = {}
   I.apply = { f = f, d = d }
   I.type = f.type(d)
   I.kind = 'apply'
   return I
end

-- @todo: overload metatable __type instead?
local function typeof(t)
   if t == nil then assert(false, "error: nil type ")
   elseif t.array2d then return 'array2d'
   elseif t.array   then return 'array'
   elseif t.type    then return typeof(t.type)
   elseif t.tuple   then return 'tuple'
   elseif t.kind == 'type' then return t.type
   else assert(false, "unknown type: " .. inspect(t))
   end
end

local function mul()
   local f = {}

   f.type = function(d)
	  assert(typeof(d.type) == 'tuple')
	  assert(typeof(d.type.tuple.a) == typeof(d.type.tuple.b))
	  return d.type.tuple.a
   end

   f.func = 'mul'
   f.kind = 'func'
   return f
end

local function elem_type(t)
   return t[typeof(t)].type
end

local function map(f)
   local I = {}
   I.map = f
   I.type = function(d)
	  if typeof(d) == 'array2d' then
		 return array2d(f.type({type = elem_type(d.type)}), d.type.array2d.w, d.type.array2d.h)
	  elseif typeof(d) == 'array' then
		 return array(f.type(d.array.type), d.array.n)
	  elseif typeof(d) == 'tuple' then
		 if typeof(d.a) == 'array2d' then
			return array2d(f.type({ a = d.a.type, b = d.b.type}), d.a.type.array2d.w, d.a.type.array2d.h)
		 else
			return array(f.type(d.a.array.type), d.a.array.n)
		 end
	  end
   end
   I.kind = 'map'
   return I
end

local function tuple(a, b)
   return { tuple = { a = a, b = b }, kind = 'type' }
end

local function zip()
   local I = {}

   I.type = function(d)
	  assert(typeof(d.a) == typeof(d.b)) -- both need to be same type of array, either both array2d or normal array, elem_type can differ
	  if typeof(d.a) == 'array2d' then
		 return array2d(tuple(elem_type(d.a.type), elem_type(d.b.type)), d.a.type.array2d.w, d.a.type.array2d.h)
	  else
		 return array(tuple(elem_type(d.a.type), elem_type(d.b.type)), d.a.type.array.n)
	  end
   end

   I.kind = 'zip'
   return I
end

--[[
   @todo implement high level language, something like:
--]]
local m = function(I) -- I is an image
   st = stencil(I, 3, 3) -- create a 3x3 stencil on the image type of I
   taps = broadcast(weights, I.w, I.h) -- w and h known at runtime
   mult = lift(function(x,y) return x*y end)
   m = map(map(mult))(zip(st,taps)) -- map the multiply over all pixels
   sum = map(reduce(sum))(m)
   return sum
end

--[[
   proving grounds
--]]

-- local test_t = array2d(array2d(uint32(), 3, 3), 1920, 1080)
-- print(inspect(test_t))
-- print_type(test_t)

local I = array2d(uint32(), 1920, 1080)

-- print(inspect(I))
-- print(inspect(stencil()))
-- print(inspect(apply(stencil(), {I = I, w = 3, h = 3})))

-- print_type(stencil())
-- print_type(apply(stencil(), {I = I, w = 3, h = 3}))

-- outdated
-- print(inspect(map(mul(), I)))

-- outdated
-- print(inspect(apply(map(mul()), I)))

-- print(inspect(I))
-- print(inspect(apply(stencil(), { I = I, w = 3, h = 3 })))
-- print(inspect(apply(map(map(mul())), apply(stencil(), { I = I, w = 3, h = 3 }))))

-- local test = map(map(mul()))
-- setmetatable(test, { __call = function(t, args) return apply(t, args) end })
-- print(inspect(test(apply(stencil(), { I = I, w = 3, h = 3 }))))

-- trying to do the equivalent of this in Haskell:
--   (map (map (uncurry (*)))) $ (map (uncurry zip) (zip st wt))
-- it would be nice to replace that last bit with just map zip (st wt) since the map is 2d-array aware right now?
-- but then this is strange since it means map is being applied to a tuple of arrays...
-- probably should leave semantics intact at least for now and require the double zip?
local I = array2d(uint32(), 1920, 1080) -- declare in image 1920x1080, type = uint32[1920x1080]
local taps = array2d(uint32(), 3, 3)    -- create 3x3 taps, type = uint32[3x3]
local st = apply(stencil(), { I = I, w = 3, h = 3 }) -- apply a stencil on the image, type = uint32[3x3][1920x1080]
local wt = apply(broadcast(), { type = taps, w = 1920, h = 1080 }) -- broadcast the taps to 1920x1080, type = uint32[3x3][1920x1080]
print(inspect(st.type))
print(inspect(wt.type))
-- local st_wt = apply(zip(), { a = st, b = wt }) -- type = {uint32[3x3], uint32[3x3]}[1920x1080]
local st_wt = apply(map(zip()), { a = st, b = wt }) -- type = {uint32, uint32}[3x3][1920x1080]
print(inspect(st_wt.type))
-- local m = apply(map(map(mul())), st_wt)

-- two ideas:
-- 1. make the functions create an AST
-- 2. make the functions return classes that can be chained into an AST

-- alternative ideas:
-- 1. same as above but creates a graph.
-- 2. the function calls instantiate modules as we go

return lang
