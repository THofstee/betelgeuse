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
#    attributes(Type t)

Module = mul
       | add
       | map(Module m)
       | reduce(Module m)
       | zip
       | zip_rec # zip_rec should be a library function that wraps a bunch of map zips
       | stencil(number w, number h)
       | broadcast(number w, number h) #what about 1d broadcast?
#       | lift # dont know how to treat this yet
       | chain(Module a, Module b)
       attributes(function type_func)
#       attributes(Type t)

# Connect(Var v, Var placeholder)
]]

-- In theory, we can do something like chain(map(*), reduce(+)) for a conv
-- @todo: maybe add a zip_rec function that recursively zip until primitive types

function L.stencil(w, h)
   local function type_func(t)
	  -- return T.array2d(t, w, h) -- need to unwrap the array2d on t first
   end
   
   return T.stencil(w, h, type_func)
end

function L.broadcast(w, h)
   local function type_func(t)
	  return T.array2d(t, w, h)
   end

   return T.broadcast(w, h, type_func)
end

function L.zip_rec()
   local function type_func(t)
	  -- return T.array
   end

   return T.zip_rec(type_func)
end

function L.mul()
   local function type_func(t)
	  -- return
   end

   return T.mul(type_func)
end

function L.add()
   local function type_func(t)
	  -- return
   end

   return T.add(type_func)
end

function L.map(m)
   local function type_func(t)
	  -- return T.array2d(m.type_func(t))
   end

   return T.map(m, type_func)
end

function L.chain(a, b)
   local function type_func(t)
	  -- return b.type_func(a.type_func(t))
   end

   return T.chain(a, b, type_func)
end

function L.reduce(m)
   local function type_func(t)
   end

   return T.reduce(m, type_func)
end

function L.apply(m, v)
   return T.apply(m, v)
end

function L.input(t)
   return T.input(t)
end

function L.array2d(t, w, h)
   return T.array2d(t, w, h)
end

function L.uint32()
   return T.uint32
end

function L.placeholder(t)
   return T.placeholder(t)
end

function L.concat(a, b)
   return T.concat(a, b)
end

local I = L.input(L.array2d(L.uint32(), 1920, 1080))
local taps = L.placeholder(L.array2d(L.uint32(), 3, 3))
local st = L.apply(L.stencil(3, 3), I)
local wt = L.apply(L.broadcast(1920, 1080), taps)
local st_wt = L.apply(L.zip_rec(), L.concat(st, wt))
local m = L.apply(L.chain(L.map(L.mul()), L.reduce(L.add())), st_wt)

print(inspect(m))
