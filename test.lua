local inspect = require 'inspect'
local asdl = require 'asdl'

local L = {}

local T = asdl.NewContext()
T:Define [[
Type = uint(number n)
     | tuple(Type a, Type b)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

# @todo: need to find a better way of dealing with these constants
Val = uint_c(number n, number c)
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
       | stencil(number w, number h)
       | pad(number u, number d, number l, number r)
       | broadcast(number w, number h) # @todo: what about 1d broadcast?
# @todo consider changing multiply etc to use the lift feature and lift systolic
#       | lift # @todo: this should raise rigel modules into this language
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
	  assert(t.kind == 'array2d', 'stencil requires input type to be of array2d')
	  return T.array2d(T.array2d(t.t, w, h), t.w, t.h)
   end
   
   return T.stencil(w, h, type_func)
end

function L.broadcast(w, h)
   local function type_func(t)
	  return T.array2d(t, w, h)
   end

   return T.broadcast(w, h, type_func)
end

function L.pad(u, d, l, r)
   local function type_func(t)
	  assert(t.kind == 'array2d', 'pad requires input type of array2d')
	  return T.array2d(t.t, t.w+l+r, t.h+u+d)
   end

   return T.pad(u, d, l, r, type_func)
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

   return T.zip(type_func)
end

function L.zip_rec()
   return function(v)
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
end

local function binop_type_func(t)
   assert(t.kind == 'tuple', 'binop requires tuple input')
   assert(t.a.kind == t.b.kind, 'binop requires both elements in tuple to be of same type')
   assert(t.a.kind == 'uint', 'binop requires primitive type')
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
	  assert(is_array_type(t), 'reduce operates on arrays')
	  return m.type_func(L.tuple(t.t, t.t))
   end

   return T.reduce(m, type_func)
end

function L.apply(m, v)
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

function L.array2d_c(t)
   return T.array2d_c(t)
end

function L.const(t, v)
   return T.const(t, v, t)
end

function L.lambda(f, x)
   local function type_func(t)
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

-- testing lambda
local x = L.input(L.uint32())
local y = L.apply(L.add(), L.concat(x, L.const(L.uint32(), T.uint_c(32, 4))))
local f = L.lambda(y, x)
local z = L.apply(f, L.const(L.uint32(), T.uint_c(32, 1)))

--[[
   tests with rigel
--]]
package.path = "/home/hofstee/rigel/?.lua;/home/hofstee/rigel/src/?.lua;/home/hofstee/rigel/examples/?.lua;" .. package.path
local R = require 'rigelSimple'
local C = require 'examplescommon'

-- add constant to image (broadcast)
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local c = L.const(L.uint8(), T.uint_c(8, 1))
local bc = L.apply(L.broadcast(im_size[1], im_size[2]), c)
local m = L.apply(L.map(L.add()), L.apply(L.zip_rec(), L.concat(I, bc)))

-- add constant to image (lambda)
local im_size = { 32, 16 }
local const_val = 30
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local x = L.input(L.uint8())
local c = L.const(L.uint8(), T.uint_c(8, const_val))
local add_c = L.lambda(L.apply(L.add(), L.concat(x, c)), x)
local m = L.apply(L.map(add_c), I)

local rtypes = require 'types'

local memoize = require 'memoize'

local translate = {}
local translate_m = {
   -- dispatch translation typechecking function thing
   __call = function(t, m)
	  if T.Type:isclassof(m) then
		 return translate.type(m)
	  elseif T.Val:isclassof(m) then
		 return translate.val(m)
	  elseif T.Var:isclassof(m) then
		 return translate.var(m)
	  elseif T.Module:isclassof(m) then
		 return translate.module(m)
	  elseif T.Connect:isclassof(m) then
		 return translate.connect(m)
	  end
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

--[[
Type = uint(number n)
     | tuple(Type a, Type b)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

# @todo: need to find a better way of dealing with these constants
Val = uint_c(number n, number c)
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
       | stencil(number w, number h)
       | pad(number u, number d, number l, number r)
       | broadcast(number w, number h) # @todo: what about 1d broadcast?
# @todo consider changing multiply etc to use the lift feature and lift systolic
#       | lift # @todo: this should raise rigel modules into this language
       | lambda(Var f, input x)
       attributes(function type_func)

Connect = connect(Var v, Var placeholder)
--]]

function translate.var(v)
   if T.input:isclassof(v) then
	  return translate.input(v)
   elseif T.const:isclassof(v) then
	  return translate.const(v)
   elseif T.concat:isclassof(v) then
	  return translate.concat(v)
   end
end
translate.var = memoize(translate.var)

function translate.const(c)
   -- print(inspect(c, {depth = 2}))
   return R.constant{
	  type = translate.type(c.type),
	  value = c.v.c
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
   end
end
translate.module = memoize(translate.module)

function translate.apply(a)
   return R.connect{
	  input = translate(a.v),
	  toModule = translate(a.m)
   }
end
translate.apply = memoize(translate.apply)

local r_I = translate.input(I)

local function add_const()
   local r_x = translate(x)
   local r_c = translate(c)
   local r_xc = translate.concat(L.concat(x, c))

   local sum = translate.apply(L.apply(L.add(), L.concat(x, c)))

   return R.defineModule{ input = r_x, output = sum }
   -- return R.defineModule{ input = r_xc.inputs[1], output = sum }
end
local mod = R.connect{
   input = r_I,
   toModule = R.modules.map{
	  fn = add_const(),
	  size = im_size
   }
}
local mod_mod = R.HS(R.defineModule{
   input = r_I,
   output = mod,
})

R.harness{ fn = mod_mod,
           inFile = "box_32_16.raw", inSize = im_size,
           outFile = "test", outSize = im_size }
-- print(inspect(mod))

-- add two image streams
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local J = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local ij = L.apply(L.zip_rec(), L.concat(I, J))
local m = L.apply(L.map(L.add()), ij)

-- convolution
local im_size = { 1920, 1080 }
local pad_size = { 1920+16, 1080+3 }
local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
local pad = L.apply(L.pad(2, 1, 8, 8), I)
local st = L.apply(L.stencil(4, 4), pad)
local taps = L.const(L.array2d(L.uint8(), 4, 4), L.array2d_c({
						   {  4, 14, 14,  4 },
						   { 14, 32, 32, 14 },
						   { 14, 32, 32, 14 },
						   {  4, 14, 14,  4 }}))
local wt = L.apply(L.broadcast(pad_size[1], pad_size[2]), taps)
local st_wt = L.apply(L.zip_rec(), L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local m = L.apply(conv, st_wt)

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
