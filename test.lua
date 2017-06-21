local inspect = require 'inspect'
local asdl = require 'asdl'

local L = {}

local T = asdl.NewContext()
T:Define [[
Type = uint32
     | tuple(Type a, Type b)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

Foo = bar(number n)

Val = (number n)

Var = input(Type t)
    | const(Type t, Val v)
    | placeholder(Type t)
    | concat(Var a, Var b)
#    | split(Var v) # does this need to exist?
    | apply(Module m, Var v)
    attributes(Type type)

Module = mul
       | add
       | map(Module m)
       | reduce(Module m)
       | zip
       | zip_rec
       | stencil(number w, number h)
       | broadcast(number w, number h) #what about 1d broadcast?
#       | lift # dont know how to treat this yet
       | chain(Module a, Module b)
       attributes(function type_func)

Connect = connect(Var v, Var placeholder)
]]

-- In theory, we can do something like chain(map(*), reduce(+)) for a conv
-- @todo: maybe add a zip_rec function that recursively zip until primitive types

function L.stencil(w, h)
   local function type_func(t)
	  print('stencil type_func')
	  assert(t.kind == 'array2d', 'stencil requires input type to be of array2d')
	  return T.array2d(T.array2d(t.t, w, h), t.w, t.h)
   end
   
   return T.stencil(w, h, type_func)
end

function L.broadcast(w, h)
   local function type_func(t)
	  print('broadcast type_func')
	  return T.array2d(t, w, h)
   end

   return T.broadcast(w, h, type_func)
end

function L.zip()
   local function type_func(t)
	  print('zip type_func')
	  assert(t.kind == 'tuple', 'zip requires input type to be tuple')
	  assert(t.a.kind == 'array' or t.a.kind == 'array2d', 'zip operates over tuple of arrays')
	  assert(t.a.kind == t.b.kind, 'cannot zip ' .. t.a.kind .. ' with ' .. t.b.kind)

	  if t.a.kind == 'array' then
		 local n = math.min(t.a.n, t.b.n)
		 return L.array(L.tuple(t.a.t, t.b.t), n)
	  else
		 local w = math.min(t.a.w, t.b.w)
		 local h = math.min(t.a.h, t.b.h)
		 return L.array2d(L.tuple(t.a.t, t.b.t), w, h)
	  end
   end

   return T.zip(type_func)
end

function L.zip_rec()
   local function type_func(t)
	  print('zip_rec type_func')
   end
   
   return T.zip_rec(type_func)
end

local function binop_type_func(t)
   print('binop type_func')
   assert(t.kind == 'tuple', 'binop requires tuple input')
   assert(t.a.kind == t.b.kind, 'binop requires both elements in tuple to be of same type')
   assert(t.a.kind == 'uint32', 'binop requires primitive type')
   return t.a
end   

function L.mul()
   return T.mul(binop_type_func)
end

function L.add()
   return T.add(binop_type_func)
end

function L.map(m)
   local function type_func(t)
	  print('map type_func')
	  assert(t.kind == 'array' or t.kind == 'array2d', 'map operates on arrays')

	  if t.kind == 'array' then
		 return L.array(m.type_func(t.t), t.n)
	  else
		 return L.array2d(m.type_func(t.t), t.w, t.h)
	  end
   end

   return T.map(m, type_func)
end

function L.chain(a, b)
   local function type_func(t)
	  print('chain type_func')
	  return b.type_func(a.type_func(t))
   end

   return T.chain(a, b, type_func)
end

function L.reduce(m)
   local function type_func(t)
	  print('reduce type_func')
	  assert(t.kind == 'array' or t.kind == 'array2d', 'reduce operates on arrays')
	  return m.type_func(L.tuple(t.t, t.t))
   end

   return T.reduce(m, type_func)
end

function L.apply(m, v)
   if m.kind == 'zip_rec' then
	  assert(v.type.kind == 'tuple')

	  local function is_array_type(t)
		 return t.kind == 'array' or t.kind == 'array2d'
	  end
	  
	  local a = v.type.a
	  local b = v.type.b
	  m = L.zip()
	  while is_array_type(a.t) and is_array_type(b.t) do
		 v = L.apply(m, v)
		 m = L.map(m) 
		 break
	  end
   end
   return T.apply(m, v, m.type_func(v.type))
end

function L.input(t)
   return T.input(t, t)
end

function L.array2d(t, w, h)
   return T.array2d(t, w, h)
end

function L.tuple(a, b)
   return T.tuple(a, b)
end

function L.uint32()
   return T.uint32
end

function L.placeholder(t)
   return T.placeholder(t, t)
end

function L.concat(a, b)
   return T.concat(a, b, L.tuple(a.type, b.type))
end

--[[
   proving grounds
--]]

-- ([uint32], [uint32]) -> [(uint32, uint32)]
-- ((uncurry zip) (a, b))
local a = L.input(L.array2d(L.uint32(), 3, 3))
local b = L.input(L.array2d(L.uint32(), 3, 3))
local c = L.apply(L.zip(), L.concat(a, b))
local d = L.apply(L.zip_rec(), L.concat(a, b))

-- ([[uint32]], [[uint32]]) -> [[(uint32, uint32)]]
-- (map (uncurry zip) ((uncurry zip) (a, b)))
local a = L.input(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5))
local b = L.input(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5))
local c = L.apply(L.map(L.zip()), L.apply(L.zip(), L.concat(a, b)))
local d = L.apply(L.zip_rec(), L.concat(a, b))

-- ([[[uint32]]], [[[uint32]]]) -> [[[(uint32, uint32)]]]
-- (map (map (uncurry zip)) (map (uncurry zip) ((uncurry zip) (a, b))))
local a = L.input(L.array2d(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5), 7, 7))
local b = L.input(L.array2d(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5), 7, 7))
local c = L.apply(L.map(L.map(L.zip())), L.apply(L.map(L.zip()), L.apply(L.zip(), L.concat(a, b))))
local d = L.apply(L.zip_rec(), L.concat(a, b))

local I = L.input(L.array2d(L.uint32(), 1920, 1080))
local taps = L.placeholder(L.array2d(L.uint32(), 3, 3))
local st = L.apply(L.stencil(3, 3), I)
local wt = L.apply(L.broadcast(1920, 1080), taps)
-- local st_wt = L.apply(L.map(L.zip()), L.apply(L.zip(), L.concat(st, wt)))
local st_wt = L.apply(L.zip_rec(), L.concat(st, wt))
local m = L.apply(L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add()))), st_wt)

print(m.type)
-- print(inspect(m.type))
