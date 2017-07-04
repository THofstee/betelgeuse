local asdl = require 'asdl'
local List = asdl.List

local L = {}

local T = asdl.NewContext()
T:Define [[
Type = uint(number n)
#     | tuple(Type a, Type b)
     | tuple(Type* ts)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

Value = input(Type t)
      | const(Type t, any v)
      | placeholder(Type t)
#      | concat(Value a, Value b)
      | concat(Value* vs)
#      | split(Value v) # @todo: does this need to exist?
      | apply(Module m, Value v)
      attributes(Type type)

Module = mul
       | add
       | map(Module m)
       | reduce(Module m)
       | zip
       | stencil(number w, number h)
       | pad(number u, number d, number l, number r)
       | broadcast(number w, number h) # @todo: what about 1d broadcast?
# @todo consider changing multiply etc to use the lift feature and lift systolic
#       | lift # @todo: this should raise rigel modules into this language
       | lambda(Value f, input x)
       attributes(function type_func)

Connect = connect(Value v, Value placeholder)
]]

local function is_array_type(t)
   return t.kind == 'array' or t.kind == 'array2d'
end

local L_mt = {
   __call = function(f, x)
	  return L.apply(f, x)
   end
}

-- @todo: maybe make this an element in the asdl rep?
-- @todo: anything that returns a module should wrap it first
local function L_wrap(m)
   return setmetatable({ internal = m, kind = 'wrapped' }, L_mt)
end

-- @todo: anything that consumes a module should unwrap it first
local function L_unwrap(w)
   return w.internal
end

function L.stencil(w, h)
   local function type_func(t)
	  assert(t.kind == 'array2d', 'stencil requires input type to be of array2d')
	  return T.array2d(T.array2d(t.t, w, h), t.w, t.h)
   end
   
   return L_wrap(T.stencil(w, h, type_func))
end

function L.broadcast(w, h)
   local function type_func(t)
	  return T.array2d(t, w, h)
   end

   return L_wrap(T.broadcast(w, h, type_func))
end

function L.pad(u, d, l, r)
   local function type_func(t)
	  assert(t.kind == 'array2d', 'pad requires input type of array2d')
	  return T.array2d(t.t, t.w+l+r, t.h+u+d)
   end

   return L_wrap(T.pad(u, d, l, r, type_func))
end

function L.zip()
   local function type_func(t)
	  assert(t.kind == 'tuple', 'zip requires input type to be tuple')
	  local arr_t = t.ts[1].kind
	  for _,t in ipairs(t.ts) do
		 assert(is_array_type(t), 'zip operates over tuple of arrays')
		 assert(t.kind == arr_t, 'cannot zip ' .. arr_t .. ' with ' .. t.kind)
	  end

	  if arr_t == 'array' then
		 local n = t.ts[1].n
		 local types = {}
		 for i,t  in ipairs(t.ts) do
			n = math.min(n, t.n)
			types[i] = t.t
		 end
		 return L.array(L.tuple(types), n)
	  else
		 local w = t.ts[1].w
		 local h = t.ts[1].h
		 local types = {}
		 for i,t  in ipairs(t.ts) do
			w = math.min(w, t.w)
			h = math.min(h, t.h)
			types[i] = t.t
		 end
		 return L.array2d(L.tuple(types), w, h)
	  end
   end

   return L_wrap(T.zip(type_func))
end

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

function L.mul()
   return L_wrap(T.mul(binop_type_func))
end

function L.add()
   return L_wrap(T.add(binop_type_func))
end

function L.map(m)
   local m = L_unwrap(m)
   
   local function type_func(t)
	  assert(is_array_type(t), 'map operates on arrays')

	  if t.kind == 'array' then
		 return L.array(m.type_func(t.t), t.n)
	  else
		 return L.array2d(m.type_func(t.t), t.w, t.h)
	  end
   end

   return L_wrap(T.map(m, type_func))
end

function L.chain(a, b)
   return L_wrap(
	  function(v)
		 return L.apply(b, L.apply(a, v))
	  end
   )
end
-- setmetatable(L.chain, L_mt)

function L.reduce(m)
   local m = L_unwrap(m)
   
   local function type_func(t)
	  assert(is_array_type(t), 'reduce operates on arrays')
	  return m.type_func(L.tuple(t.t, t.t))
   end

   return L_wrap(T.reduce(m, type_func))
end

function L.apply(m, v)
   local m = L_unwrap(m)

   if type(m) == 'function' then
	  return m(v)
   else
	  return T.apply(m, v, m.type_func(v.type))
   end
end

function L.input(t)
   return T.input(t, t)
end

function L.array(t, n)
   return T.array(t, n)
end

function L.array2d(t, w, h)
   return T.array2d(t, w, h)
end

function L.tuple(...)
   if List:isclassof(...) then
	  return T.tuple(...)
   elseif #{...} == 1 then
	  return T.tuple(List(...))
   else
	  return T.tuple(List{...})
   end
end

function L.uint32()
   return T.uint(32)
end

function L.uint8()
   return T.uint(8)
end

function L.placeholder(t)
   return T.placeholder(t, t)
end

function L.concat(...)
   local t = {}
   for i,v in ipairs({...}) do
	  t[i] = v.type
   end
   
   return T.concat(List{...}, L.tuple(t))
end

function L.const(t, v)
   return T.const(t, v, t)
end

function L.lambda(f, x)
   local function type_func(t)
	  assert(tostring(x.type) == tostring(t))
	  return f.type
   end

   return L_wrap(T.lambda(f, x, type_func))
end

function L.import()
   for name, fun in pairs(L) do
	  rawset(_G, name, fun)
   end
end

L.raw = T

L.unwrap = L_unwrap

return L
