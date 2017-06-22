local inspect = require 'inspect'
local asdl = require 'asdl'

local L = {}

local T = asdl.NewContext()
T:Define [[
Type = uint32
     | tuple(Type a, Type b)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

# @todo: need to find a better way of dealing with these constants
Val = uint32_c(number n)
    | array2d_c(table t)

Var = input(Type t)
    | const(Type t, Val v)
    | placeholder(Type t)
    | concat(Var a, Var b)
#    | split(Var v) # @todo: does this need to exist?
    | apply(Module m, Var v)
    attributes(Type type)

Module = mul
       | add
       | map(Module m)
       | reduce(Module m)
       | zip
       | zip_rec
       | stencil(number w, number h)
       | broadcast(number w, number h) # @todo: what about 1d broadcast?
#       | lift # @todo: dont know how to treat this yet
       | lambda(Var f, input x)
       attributes(function type_func)

Connect = connect(Var v, Var placeholder)
]]

local function is_array_type(t)
   return t.kind == 'array' or t.kind == 'array2d'
end

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
	  assert(is_array_type(t.a), 'zip operates over tuple of arrays')
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

	  local bt = {}
	  local idx = 1
	  local a = t.a
	  local b = t.b
	  while is_array_type(a) and is_array_type(b) do
		 bt[idx] = a
		 idx = idx + 1
		 a = a.t
		 b = b.t
	  end

	  local t = L.tuple(a, b)
	  while idx > 1 do
		 idx = idx - 1
		 if bt[idx].kind == 'array' then
			t = L.array(t, bt[idx].n)
		 else
			t = L.array2d(t, bt[idx].w, bt[idx].h)
		 end
	  end

	  return t
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
	  assert(is_array_type(t), 'map operates on arrays')

	  if t.kind == 'array' then
		 return L.array(m.type_func(t.t), t.n)
	  else
		 return L.array2d(m.type_func(t.t), t.w, t.h)
	  end
   end

   return T.map(m, type_func)
end

function L.chain(a, b)
   return function(v)
	  return L.apply(b, L.apply(a, v))
   end
end

function L.reduce(m)
   local function type_func(t)
	  print('reduce type_func')
	  assert(is_array_type(t), 'reduce operates on arrays')
	  return m.type_func(L.tuple(t.t, t.t))
   end

   return T.reduce(m, type_func)
end

function L.apply(m, v)
   if type(m) == 'function' then
	  return m(v)
   else
	  local function expand_zip_rec(m, v)
		 if m.kind == 'zip_rec' then
			assert(v.type.kind == 'tuple')
			
			m = L.zip()
			local a = v.type.a
			local b = v.type.b
			while is_array_type(a.t) and is_array_type(b.t) do
			   v = L.apply(m, v)
			   m = L.map(m)
			   
			   a = a.t
			   b = b.t
			end
		 end
		 
		 return m, v
	  end
	  
	  m, v = expand_zip_rec(m, v)
	  
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

function L.array2d_c(t)
   return T.array2d_c(t)
end

function L.const(t, v)
   return T.const(t, v, t)
end

function L.lambda(f, x)
   function type_func(t)
	  assert(tostring(x.type) == tostring(t))
	  return f.type
   end

   return T.lambda(f, x, type_func)
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
assert(tostring(c.type) == tostring(d.type))

-- ([[uint32]], [[uint32]]) -> [[(uint32, uint32)]]
-- (map (uncurry zip) ((uncurry zip) (a, b)))
local a = L.input(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5))
local b = L.input(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5))
local c = L.apply(L.map(L.zip()), L.apply(L.zip(), L.concat(a, b)))
local d = L.apply(L.zip_rec(), L.concat(a, b))
assert(tostring(c.type) == tostring(d.type))

-- ([[[uint32]]], [[[uint32]]]) -> [[[(uint32, uint32)]]]
-- (map (map (uncurry zip)) (map (uncurry zip) ((uncurry zip) (a, b))))
local a = L.input(L.array2d(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5), 7, 7))
local b = L.input(L.array2d(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5), 7, 7))
local c = L.apply(L.map(L.map(L.zip())), L.apply(L.map(L.zip()), L.apply(L.zip(), L.concat(a, b))))
local d = L.apply(L.zip_rec(), L.concat(a, b))
assert(tostring(c.type) == tostring(d.type))

-- convolution
local I = L.input(L.array2d(L.uint32(), 1920, 1080))
local taps = L.const(L.array2d(L.uint32(), 4, 4),L.array2d_c({
						   {  4, 14, 14,  4 },
						   { 14, 32, 32, 14 },
						   { 14, 32, 32, 14 },
						   {  4, 14, 14,  4 }}))
local st = L.apply(L.stencil(4, 4), I)
local wt = L.apply(L.broadcast(1920, 1080), taps)
local st_wt = L.apply(L.zip_rec(), L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local m = L.apply(conv, st_wt)
print(m)
-- print(m.type)
-- print(inspect(m.type))

local a = L.input(L.uint32())
local b = L.input(L.uint32())
local ab = L.concat(a, b)
local c = L.apply(L.add(), ab)
local d = L.apply(L.mul(), ab)
local cd = L.concat(c, d)
local e = L.apply(L.add(), cd)
-- print(inspect(e, { depth = 3 }))

local x = L.input(L.uint32())
local y = L.apply(L.add(), L.concat(x, L.const(L.uint32(), T.uint32_c(4))))
local f = L.lambda(y, x)
local z = L.apply(f, L.const(L.uint32(), T.uint32_c(1)))
print(z)

package.path = "/home/hofstee/rigel/?.lua;/home/hofstee/rigel/src/?.lua;/home/hofstee/rigel/examples/?.lua;" .. package.path
local R = require 'rigelSimple'

P = 1/4
inSize = { 1920, 1080 }
padSize = { 1920+16, 1080+3 }

function makePartialConvolve()
  local convolveInput = R.input( R.array2d(R.uint8,4*P,4) )

  local filterCoeff = R.connect{ input=nil, toModule =
    R.modules.constSeq{ type=R.array2d(R.uint8,4,4), P=P, value = 
      { 4, 14, 14,  4,
        14, 32, 32, 14,
        14, 32, 32, 14,
        4, 14, 14,  4} } }
                                   
  local merged = R.connect{ input = R.concat{ convolveInput, filterCoeff }, 
    toModule = R.modules.SoAtoAoS{ type={R.uint8,R.uint8}, size={4*P,4} } }
  
  local partials = R.connect{ input = merged, toModule =
    R.modules.map{ fn = R.modules.mult{ inType = R.uint8, outType = R.uint32}, 
                   size={4*P,4} } }
  
  local sum = R.connect{ input = partials, toModule =
    R.modules.reduce{ fn = R.modules.sum{ inType = R.uint32, outType = R.uint32 }, 
                      size={4*P,4} } }
  
  return R.defineModule{ input = convolveInput, output = sum }
end

----------------
input = R.input( R.HS( R.array( R.uint8, 1) ) )

padded = R.connect{ input=input, toModule = 
  R.HS(R.modules.padSeq{ type = R.uint8, V=1, size=inSize, pad={8,8,2,1}, value=0})}

stenciled = R.connect{ input=padded, toModule =
  R.HS(R.modules.linebuffer{ type=R.uint8, V=1, size=padSize, stencil={-3,0,-3,0}})}

-- split stencil into columns
partialStencil = R.connect{ input=stenciled, toModule=
  R.HS(R.modules.devectorize{ type=R.uint8, H=4, V=1/P}) }

-- perform partial convolution
partialConvolved = R.connect{ input = partialStencil, toModule = 
  R.HS(makePartialConvolve()) }

-- sum partial convolutions to calculate full convolution
summedPartials = R.connect{ input=partialConvolved, toModule =
  R.HS(R.modules.reduceSeq{ fn = 
    R.modules.sumAsync{ inType = R.uint32, outType = R.uint32 }, V=1/P}) }

convolved = R.connect{ input = summedPartials, toModule = 
  R.HS(R.modules.shiftAndCast{ inType = R.uint32, outType = R.uint8, shift = 8 }) }

output = R.connect{ input = convolved, toModule = 
  R.HS(R.modules.cropSeq{ type = R.uint8, V=1, size=padSize, crop={9,7,3,0} }) }


convolveFunction = R.defineModule{ input = input, output = output }
----------------

R.harness{ fn = convolveFunction,
           inFile = "1080p.raw", inSize = inSize,
           outFile = "convolve_slow", outSize = inSize }
