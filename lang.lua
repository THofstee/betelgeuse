--- A high level language for Rigel.
-- @module lang
local asdl = require 'asdl'
local List = asdl.List

local L = {}

local T = asdl.NewContext()
T:Define [[
Type = uint(number n)
     | tuple(Type* ts)
     | array2d(Type t, number w, number h)

Value = input(Type t)
      | const(Type t, any v)
      | placeholder(Type t)
      | concat(Value* vs) # @todo: it might be nice if i can index this with [n]
#      | split(Value v) # @todo: does this need to exist?
      | apply(Module m, Value v)
      attributes(Type type)

Module = mul
       | add
       | map(Module m)
       | reduce(Module m)
       | zip
       | stencil(number offset_x, number offset_y, number extent_x, number extent_y)
       | pad(number left, number right, number top, number bottom)
       | crop(number left, number right, number top, number bottom)
# @todo: try to figure out how to remove broadcast entirely, or at least w/h
       | broadcast(number w, number h) # @todo: what about 1d broadcast?
# @todo: consider changing multiply etc to use the lift feature and lift systolic
#       | lift # @todo: this should raise rigel modules into this language
       | lambda(Value f, input x)
       attributes(function type_func)

# Connect = connect(Value v, Value placeholder)
]]

local function is_array_type(t)
   return t.kind == 'array2d'
end

local L_mt = {
   __call = function(f, x)
	  return L.apply(f, x)
   end
}

-- @todo: maybe make this an element in the asdl rep?
local function L_wrap(m)
   return setmetatable({ internal = m, kind = 'wrapped' }, L_mt)
end

local function L_unwrap(w)
   return w.internal
end

--- Returns a module that will create a stencil of the image at every input.
-- [a] -> [[a]]
function L.stencil(off_x, off_y, ext_x, ext_y)
   local function type_func(t)
	  assert(t.kind == 'array2d', 'stencil requires input type to be of array2d')
	  return T.array2d(T.array2d(t.t, ext_x, ext_y), t.w, t.h)
   end
   
   return L_wrap(T.stencil(off_x, off_y, ext_x, ext_y, type_func))
end

--- Returns a module that will duplicate the input to a 2d array.
-- This module will return a 2d array where every element is equal to the input once applied.
-- a -> [a]
function L.broadcast(w, h)
   local function type_func(t)
	  return T.array2d(t, w, h)
   end

   return L_wrap(T.broadcast(w, h, type_func))
end

--- Returns a module that will pad the input by a specified amount.
function L.pad(left, right, top, bottom)
   local function type_func(t)
	  assert(t.kind == 'array2d', 'pad requires input type of array2d')
	  return T.array2d(t.t, t.w+left+right, t.h+top+bottom)
   end

   return L_wrap(T.pad(left, right, top, bottom, type_func))
end

--- Returns a module that will crop the input by a specified amount.
function L.crop(left, right, top, bottom)
   local function type_func(t)
	  assert(t.kind == 'array2d', 'crop requires input type of array2d')
	  return T.array2d(t.t, t.w-left-right, t.h-top-bottom)
   end

   return L_wrap(T.crop(left, right, top, bottom, type_func))
end

--- Returns a module that will zip two inputs together.
-- ([a], [b]) -> [(a, b)].
function L.zip()
   local function type_func(t)
	  assert(t.kind == 'tuple', 'zip requires input type to be tuple')
	  for _,t in ipairs(t.ts) do
		 assert(is_array_type(t), 'zip operates over tuple of arrays')
	  end

	  local w = t.ts[1].w
	  local h = t.ts[1].h
	  local types = {}
	  for i,t  in ipairs(t.ts) do
		 assert(t.w == w and t.h == h, 'inputs must have same array dimensions')
		 types[i] = t.t
	  end
	  return L.array2d(L.tuple(types), w, h)
   end

   return L_wrap(T.zip(type_func))
end

--- Returns a module that will recursively zip inputs.
-- Given a tuple of inputs, it will recursively apply maps of zips while all inputs share the same outer array type.
-- For example, ([[[a]]], [[b]]) -> [[([a], b)]].
function L.zip_rec()
   return L_wrap(
	  function(v)
		 assert(v.type.kind == 'tuple')

		 local m = L.zip()
		 local types = {}
		 for i,t in ipairs(v.type.ts) do
			types[i] = t
		 end
		 
		 local function all_array_t()
			if not is_array_type(types[1]) then
			   return false
			end
			
			local arr_t = types[1].kind			
			for _,t in ipairs(types) do
			   if not t.kind == arr_t then
				  return false
			   end
			end
			return true
		 end

		 while all_array_t() do
			v = L.apply(m, v)
			m = L.map(m)

			for i,t in ipairs(types) do
			   types[i] = t.t
			end
		 end
		 
		 return v
	  end
   )
end

local function binop_type_func(t)
   assert(t.kind == 'tuple', 'binop requires tuple input')
   assert(#t.ts == 2, 'binop works on two elements')
   assert(t.ts[1].kind == t.ts[2].kind, 'binop requires both elements in tuple to be of same type')
   assert(t.ts[1].kind == 'uint', 'binop requires primitive type')
   return t.ts[1]
end   

--- Returns a module that multiplies two primitive types.
function L.mul()
   return L_wrap(T.mul(binop_type_func))
end

--- Returns a module that adds two primitive types.
function L.add()
   return L_wrap(T.add(binop_type_func))
end

--- Returns a module that is a map given a module to apply.
function L.map(m)
   local m = L_unwrap(m)
   
   local function type_func(t)
	  assert(is_array_type(t), 'map operates on arrays')
	  return L.array2d(m.type_func(t.t), t.w, t.h)
   end

   return L_wrap(T.map(m, type_func))
end

--- Returns a module that is a sequence of modules being applied,
function L.chain(...)
   -- save varargs so returned function can use them
   local ms = {}
   for i,m in ipairs({...}) do
	  ms[i] = m
   end
   
   return L_wrap(
	  function(v)
		 for _,m in ipairs(ms) do
			v = L.apply(m, v)
		 end
		 return v
	  end
   )
end

--- Returns a module that is a reduce given the provided module.
-- This is implemented using a tree-reduction.
function L.reduce(m)
   local m = L_unwrap(m)
   
   local function type_func(t)
	  assert(is_array_type(t), 'reduce operates on arrays')
	  return m.type_func(L.tuple(t.t, t.t))
   end

   return L_wrap(T.reduce(m, type_func))
end

--- Applies the module on the provided value.
function L.apply(m, v)
   local m = L_unwrap(m)

   if type(m) == 'function' then
	  return m(v)
   else
	  return T.apply(m, v, m.type_func(v.type))
   end
end

--- Creates an input value given a type.
function L.input(t)
   return T.input(t, t)
end

--- Creates a 1d array type.
function L.array(t, n)
   return T.array2d(t, n, 1)
end

--- Creates a 2d array type.
function L.array2d(t, w, h)
   return T.array2d(t, w, h)
end

--- Creates a tuple type given any number of types.
function L.tuple(...)
   if List:isclassof(...) then
	  return T.tuple(...)
   elseif #{...} == 1 then
	  return T.tuple(List(...))
   else
	  return T.tuple(List{...})
   end
end

--- A shorthand for uint(32)
function L.uint32()
   return T.uint(32)
end
-- L.uint32 = T.uint(32)

--- A shorthand for uint(8)
function L.uint8()
   return T.uint(8)
end
-- L.uint8 = T.uint(8)

--- A placeholder that can be replaced later.
-- This might be needed for feedback loops.
-- @todo: figure out if this is actually needed.
-- @tparam Type t the type of the placeholder
function L.placeholder(t)
   return T.placeholder(t, t)
end

--- Concatenates any number of values.
function L.concat(...)
   local t = {}
   for i,v in ipairs({...}) do
	  t[i] = v.type
   end
   
   return T.concat(List{...}, L.tuple(t))
end

--- Returns a compile-time constant.
function L.const(t, v)
   return T.const(t, v, t)
end

--- Creates a module given a value and an input variable.
function L.lambda(f, x)
   local function type_func(t)
	  assert(tostring(x.type) == tostring(t))
	  return f.type
   end

   return L_wrap(T.lambda(f, x, type_func))
end

--- Exports library functions to the global namespace.
function L.import()
   local reserved = {
	  import = true,
	  debug = true,
   }
   
   for name, fun in pairs(L) do
	  if not reserved[name] then
		 rawset(_G, name, fun)
	  end
   end
end

L.raw = T

L.unwrap = L_unwrap

return L
