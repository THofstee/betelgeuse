local inspect = require 'inspect'
local asdl = require 'asdl'

local L = {}

local T = asdl.NewContext()
T:Define [[
Type = uint(number n)
     | tuple(Type a, Type b)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

Value = input(Type t)
    | const(Type t, any v)
    | placeholder(Type t)
    | concat(Value a, Value b)
#    | split(Value v) # @todo: does this need to exist?
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

-- @todo: need to figure out how to actually implement syntax sugar. since the L.xxx are functions that return T.xxx, where the T.xxx have metatables i shouldn't touch, so i might need to wrap everything in a wrapper table...
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

   return L_wrap(T.zip(type_func))
end

function L.zip_rec()
   return L_wrap(
	  function(v)
		 assert(v.type.kind == 'tuple')

		 local m = L.zip()
		 local a = v.type.a
		 local b = v.type.b
		 while is_array_type(a.t) and is_array_type(b.t) do
			v = L.apply(m, v)
			m = L.map(m)
			
			a = a.t
			b = b.t
		 end
		 
		 return L.apply(m, v)
	  end
   )
end

local function binop_type_func(t)
   assert(t.kind == 'tuple', 'binop requires tuple input')
   assert(t.a.kind == t.b.kind, 'binop requires both elements in tuple to be of same type')
   assert(t.a.kind == 'uint', 'binop requires primitive type')
   return t.a
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

function L.tuple(a, b)
   return T.tuple(a, b)
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

function L.concat(a, b)
   return T.concat(a, b, L.tuple(a.type, b.type))
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

--[[
   proving grounds
--]]

-- ([uint32], [uint32]) -> [(uint32, uint32)]
-- ((uncurry zip) (a, b))
local a = L.input(L.array2d(L.uint32(), 3, 3))
local b = L.input(L.array2d(L.uint32(), 3, 3))
local c = L.zip()(L.concat(a, b))
local d = L.zip_rec()(L.concat(a, b))
assert(tostring(c.type) == tostring(d.type))

-- ([[uint32]], [[uint32]]) -> [[(uint32, uint32)]]
-- (map (uncurry zip) ((uncurry zip) (a, b)))
local a = L.input(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5))
local b = L.input(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5))
local c = L.map(L.zip())(L.zip()(L.concat(a, b)))
local d = L.zip_rec()(L.concat(a, b))
assert(tostring(c.type) == tostring(d.type))

-- ([[[uint32]]], [[[uint32]]]) -> [[[(uint32, uint32)]]]
-- (map (map (uncurry zip)) (map (uncurry zip) ((uncurry zip) (a, b))))
local a = L.input(L.array2d(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5), 7, 7))
local b = L.input(L.array2d(L.array2d(L.array2d(L.uint32(), 3, 3), 5, 5), 7, 7))
local c = L.map(L.map(L.zip()))(L.map(L.zip())(L.zip()(L.concat(a, b))))
local d = L.zip_rec()(L.concat(a, b))
assert(tostring(c.type) == tostring(d.type))

-- testing lambda
local x = L.input(L.uint32())
local y = L.add()(L.concat(x, L.const(L.uint32(), 4)))
local f = L.lambda(y, x)
local z = f(L.const(L.uint32(), 1))

--[[
   tests with rigel
--]]
package.path = "/home/hofstee/rigel/?.lua;/home/hofstee/rigel/src/?.lua;/home/hofstee/rigel/examples/?.lua;" .. package.path
local R = require 'rigelSimple'
local C = require 'examplescommon'
local rtypes = require 'types'
local memoize = require 'memoize'

local translate = {}
local translate_m = {
   -- dispatch translation typechecking function thing
   __call = function(t, m)
	  if m.kind == 'wrapped' then
		 m = L_unwrap(m)
	  end

	  return translate[m.kind](m)
	  
	  -- if T.Type:isclassof(m) then
	  -- 	 return translate.type(m)
	  -- elseif T.Value:isclassof(m) then
	  -- 	 return translate.value(m)
	  -- elseif T.Module:isclassof(m) then
	  -- 	 return translate.module(m)
	  -- elseif T.Connect:isclassof(m) then
	  -- 	 return translate.connect(m)
	  -- end
   end
}
setmetatable(translate, translate_m)

function translate.type(t)
   if T.array2d:isclassof(t) then
	  return R.array2d(translate.type(t.t), t.w, t.h)
   elseif T.array:isclassof(t) then
	  return R.array(translate.type(t.t), t.n)
   elseif T.uint:isclassof(t) then
	  return rtypes.uint(t.n)
   end
end
translate.type = memoize(translate.type)

function translate.input(i)
   return R.input(translate.type(i.type))
end
translate.input = memoize(translate.input)

function translate.value(v)
   if T.input:isclassof(v) then
	  return translate.input(v)
   elseif T.const:isclassof(v) then
	  return translate.const(v)
   elseif T.concat:isclassof(v) then
	  return translate.concat(v)
   elseif T.apply:isclassof(v) then
	  return translate.apply(v)
   end
end
translate.value = memoize(translate.value)

function translate.const(c)
   return R.constant{
	  type = translate.type(c.type),
	  value = c.v
   }
end
translate.const = memoize(translate.const)

function translate.concat(c)
   return R.concat{ translate(c.a), translate(c.b) }
end
translate.concat = memoize(translate.concat)

function translate.add(m)
   return R.modules.sum{
	  inType = R.uint8,
	  outType = R.uint8
   }
end
translate.add = memoize(translate.add)

function translate.module(m)
   if T.add:isclassof(m) then
	  return translate.add(m)
   elseif T.map:isclassof(m) then
	  return translate.map(m)
   elseif T.lambda:isclassof(m) then
	  return translate.lambda(m)
   end
end
translate.module = memoize(translate.module)

function translate.apply(a)
   -- propagate output type back to the module
   local m = a.m
   m.type = a.type
   
   return R.connect{
	  input = translate(a.v),
	  toModule = translate(m)
   }
end
translate.apply = memoize(translate.apply)

function translate.lambda(l)
   return R.defineModule{
	  input = translate(l.x),
	  output = translate(l.f)
   }
end
translate.lambda = memoize(translate.lambda)

function translate.map(m)
   local size
   if T.array:isclassof(m.type) then
	  size = { m.type.n }
   elseif T.array2d:isclassof(m.type) then
	  size = { m.type.w, m.type.h }
   end
   
   return R.modules.map{
	  fn = translate(m.m),
	  size = size
   }
end
translate.map = memoize(translate.map)

-- add constant to image (broadcast)
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local c = L.const(L.uint8(), 1)
local bc = L.broadcast(im_size[1], im_size[2])(c)
local m = L.map(L.add())(L.zip_rec()(L.concat(I, bc)))

-- add constant to image (lambda)
local im_size = { 32, 16 }
local const_val = 30
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local x = L.input(L.uint8())
local c = L.const(L.uint8(), const_val)
local add_c = L.lambda(L.add()(L.concat(x, c)), x)
local m_add = L.map(add_c)

-- could sort of metaprogram the thing like this, and postpone generation of the module until later
-- you could create a different function that would take in something like a filename and then generate these properties in the function and pass it in to the module generation
local function create_module(size)
   local const_val = 30
   local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
   local x = L.input(L.uint8())
   local c = L.const(L.uint8(), const_val)
   local add_c = L.lambda(L.add()(L.concat(x, c)), x)
   local m_add = L.map(add_c)
   return L.lambda(m_add(I), I)
end
local m = create_module(im_size)

-- write_file('box_out.raw', m(read_file('box_32_16.raw')))

local rigel_out = translate(m_add(I))

-- partialStencil = R.connect{ input=stenciled, toModule=
--   R.HS(R.modules.devectorize{ type=R.uint8, H=4, V=1/P}) }


-- this function spits back the utilization of the module
print(inspect(rigel_out:calcSdfRate(rigel_out)))

-- vectorize -> module -> devectorize
-- idea: change the module to a streaming interface by stamping out the module internally wxh times, then reduce internally until utilization is 100%

-- @todo: do i want to represent this in my higher level language instead as an internal feature (possibly useful too for users) and then translate to rigel instead?
-- converts a module to operate on streams instead of full images
local function streamify(m)
   local stream_in = R.input(R.HS(R.uint8))

   local vec_in = R.connect{
	  input = R.input(R.HS(R.uint8)),
	  toModule = R.HS(
		 R.modules.vectorize{
			type = R.uint8,
			H = 1,
			V = im_size[1]*im_size[2]
		 }
	  )
   }

   local cast_in = R.connect{
	  input = vec_in,
	  toModule = R.HS(
		 C.cast(
			R.array2d(R.uint8, im_size[1]*im_size[2], 1),
			R.array2d(R.uint8, im_size[1], im_size[2])
		 )
	  )
   }

   local vec_out = R.connect{
	  input = cast_in,
	  toModule = R.HS(m)
   }

   local cast_out = R.connect{
	  input = vec_out,
	  toModule = R.HS(
		 C.cast(
			R.array2d(R.uint8, im_size[1], im_size[2]),
			R.array2d(R.uint8, im_size[1]*im_size[2], 1)
		 )
	  )
   }

   local stream_out = R.connect{
	  input = cast_out,
	  toModule = R.HS(
		 R.modules.devectorize{
			type = R.uint8,
			H = 1,
			V = im_size[1]*im_size[2],
		 }
	  )
   }

   return vec_out, stream_out
end

local dut, stream_out = streamify(translate(m))
print(inspect(dut:calcSdfRate(stream_out)))

local r_m = translate(m)
R.harness{ fn = R.HS(r_m),
           inFile = "box_32_16.raw", inSize = im_size,
           outFile = "test", outSize = im_size }

-- add two image streams
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local J = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local ij = L.zip_rec()(L.concat(I, J))
local m = L.map(L.add())(ij)

-- convolution
local im_size = { 1920, 1080 }
local pad_size = { 1920+16, 1080+3 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.pad(2, 1, 8, 8)(I)
local st = L.stencil(4, 4)(pad)
local taps = L.const(L.array2d(L.uint8(), 4, 4), {
						   {  4, 14, 14,  4 },
						   { 14, 32, 32, 14 },
						   { 14, 32, 32, 14 },
						   {  4, 14, 14,  4 }})
local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
local st_wt = L.zip_rec()(L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local m = conv(st_wt)
local m2 = L.map(L.reduce(L.add()))(L.map(L.map(L.mul()))(st_wt))

-----

-- local function f(a, b, c)
--    if type(a) == 'table' then
-- 	  local t = a
-- 	  a = t.a
-- 	  b = t.b
-- 	  c = t.c
--    end
   
--    print(a, b, c)
-- end

-- local function fff(...)
--    local a, b, c = ...
--    if type(...) == 'table' then
-- 	  local t = ...
-- 	  a = t.a
-- 	  b = t.b
-- 	  c = t.c
--    end

--    print(a, b, c)
-- end

-- f(1, 2, 3)
-- f{ c = 3, b = 2, a = 1 }

-- fff(1, 2, 3)
-- fff{ c = 3, b = 2, a = 1 }

P = 1/4
inSize = { 1920, 1080 }
padSize = { 1920+16, 1080+3 }

-- Flatten an n*m table into a 1*(n*m) table
local function flatten_mat(m)
   local idx = 0
   local res = {}
   
   for h,row in ipairs(m) do
	  for w,elem in ipairs(row) do
		 idx = idx + 1
		 res[idx] = elem
	  end
   end
   
   return res
end

-- local input = R.input(R.array2d(R.uint8, 1920, 1080))
-- local padded = R.connect{
--    input = input,
--    toModule = R.modules.padSeq{
-- 	  type = R.uint8,
-- 	  V = 1,
-- 	  size = inSize,
-- 	  pad = { 8, 8, 2, 1 },
-- 	  value = 0
--    }
-- }
-- local st = R.connect{
--    input = padded,
--    toModule = C.stencil(
-- 	  R.uint8,    -- A
-- 	  padSize[1], -- w
-- 	  padSize[2], -- h
-- 	  -4,         -- xmin
-- 	  0,          -- xmax
-- 	  -4,         -- ymin
-- 	  0           -- ymax
--    )
-- }
-- local taps = R.modules.constSeq{
--    type = R.array2d(R.uint8, 4, 4),
--    P = P,
--    value = flatten_mat({
-- 		 {  4, 14, 14,  4 },
-- 		 { 14, 32, 32, 14 },
-- 		 { 14, 32, 32, 14 },
-- 		 {  4, 14, 14,  4 }
--    })
-- }
-- -- local wt = R.connect{
-- --    input = taps,
-- --    toModule = C.broadcast(
-- -- 	  R.array2d(R.uint8, 4, 4), -- A
-- -- 	  1920                      -- T
-- --    )
-- -- }
-- local st_wt = something
-- local conv = idk
-- local m = thing
-----

-- function makePartialConvolve()
--   local convolveInput = R.input( R.array2d(R.uint8,4*P,4) )

--   local filterCoeff = R.connect{ input=nil, toModule =
--     R.modules.constSeq{ type=R.array2d(R.uint8,4,4), P=P, value = 
--       { 4, 14, 14,  4,
--         14, 32, 32, 14,
--         14, 32, 32, 14,
--         4, 14, 14,  4} } }
                                   
--   local merged = R.connect{ input = R.concat{ convolveInput, filterCoeff }, 
--     toModule = R.modules.SoAtoAoS{ type={R.uint8,R.uint8}, size={4*P,4} } }
  
--   local partials = R.connect{ input = merged, toModule =
--     R.modules.map{ fn = R.modules.mult{ inType = R.uint8, outType = R.uint32}, 
--                    size={4*P,4} } }
  
--   local sum = R.connect{ input = partials, toModule =
--     R.modules.reduce{ fn = R.modules.sum{ inType = R.uint32, outType = R.uint32 }, 
--                       size={4*P,4} } }
  
--   return R.defineModule{ input = convolveInput, output = sum }
-- end

-- ----------------
-- input = R.input( R.HS( R.array( R.uint8, 1) ) )

-- padded = R.connect{ input=input, toModule = 
--   R.HS(R.modules.padSeq{ type = R.uint8, V=1, size=inSize, pad={8,8,2,1}, value=0})}

-- stenciled = R.connect{ input=padded, toModule =
--   R.HS(R.modules.linebuffer{ type=R.uint8, V=1, size=padSize, stencil={-3,0,-3,0}})}

-- -- split stencil into columns
-- partialStencil = R.connect{ input=stenciled, toModule=
--   R.HS(R.modules.devectorize{ type=R.uint8, H=4, V=1/P}) }

-- -- perform partial convolution
-- partialConvolved = R.connect{ input = partialStencil, toModule = 
--   R.HS(makePartialConvolve()) }

-- -- sum partial convolutions to calculate full convolution
-- summedPartials = R.connect{ input=partialConvolved, toModule =
--   R.HS(R.modules.reduceSeq{ fn = 
--     R.modules.sumAsync{ inType = R.uint32, outType = R.uint32 }, V=1/P}) }

-- convolved = R.connect{ input = summedPartials, toModule = 
--   R.HS(R.modules.shiftAndCast{ inType = R.uint32, outType = R.uint8, shift = 8 }) }

-- output = R.connect{ input = convolved, toModule = 
--   R.HS(R.modules.cropSeq{ type = R.uint8, V=1, size=padSize, crop={9,7,3,0} }) }


-- convolveFunction = R.defineModule{ input = input, output = output }
-- ----------------

-- R.harness{ fn = convolveFunction,
--            inFile = "1080p.raw", inSize = inSize,
--            outFile = "convolve_slow", outSize = inSize }
