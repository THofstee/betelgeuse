local inspect = require 'inspect'

-- @todo: fix type representation

local function uint32()
   return { type = 'uint32', kind = 'type' }
end

local function array(t, n)
   return { array = { n = n, type = t }, type = 'array', kind = 'type' }
end

local function array2d(t, w, h)
   return { array2d = { w = w, h = h, type = t }, type = 'array2d', kind = 'type' }
end

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


-- local test_t = array2d(array2d(uint32(), 3, 3), 1920, 1080)
-- print(inspect(test_t))
-- print_type(test_t)

local I = array2d(uint32(), 1920, 1080)

local function stencil()
   local f = {}

   f.type = function(d)
	  return array2d(array2d(d.I.array2d.type, d.w, d.h), d.I.array2d.w, d.I.array2d.h)
   end
   
   f.func = 'stencil'
   f.kind = 'func'
   return f
end

local function apply(f, d)
   local I = {}
   I.apply = { f = f, d = d }
   I.type = f.type(d)
   I.kind = 'apply'
   return I
end

local function mul()
   local f = {}

   f.type = function(d)
	  return d.type
   end

   f.func = 'mul'
   f.kind = 'func'
   return f
end

local function typeof(t)
   if t == nil then assert(false, "error: nil type ")
   elseif t.array2d then return 'array2d'
   elseif t.array   then return 'array'
   else assert(false, "unknown type: " .. t)
   end
end

local function elem_type(t)
   return t[typeof(t)].type
end

local function map(f)
   local I = {}
   I.map = f
   I.type = function(d)
	  if typeof(d.type) == 'array2d' then
		 return array2d(f.type({type = elem_type(d.type)}), d.type.array2d.w, d.type.array2d.h)
	  else
		 return array(f.type(d.array.type), d.array.n)
	  end
   end
   I.kind = 'map'
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

-- print(inspect(I))
-- print(inspect(stencil()))
-- print(inspect(apply(stencil(), {I = I, w = 3, h = 3})))

-- print_type(stencil())
-- print_type(apply(stencil(), {I = I, w = 3, h = 3}))

-- outdated
-- print(inspect(map(mul(), I)))

-- outdated
-- print(inspect(apply(map(mul()), I)))

print(inspect(I))
print(inspect(apply(stencil(), {I = I, w = 3, h = 3})))
print(inspect(apply(map(map(mul())), apply(stencil(), {I = I, w = 3, h = 3}))))

local test = map(map(mul()))
setmetatable(test, { __call = function(t, args) return apply(t, args) end })
print(inspect(test(apply(stencil(), { I = I, w = 3, h = 3 }))))

-- two ideas:
-- 1. make the functions create an AST
-- 2. make the functions return classes that can be chained into an AST

-- alternative ideas:
-- 1. same as above but creates a graph.
-- 2. the function calls instantiate modules as we go

