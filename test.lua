local inspect = require 'inspect'
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
		 
		 return v --L.apply(m, v)
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
	  print(m)
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

-- function L.tuple(a, b)
--    return T.tuple(a, b)
-- end

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

-- function L.concat(a, b)
--    return T.concat(a, b, L.tuple(a.type, b.type))
-- end

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

local dispatch_mt = {
   __call = function(t, m)
	  return t[m.kind](m)
   end
}
local translate = {}
setmetatable(translate, dispatch_mt)

function translate.wrapped(w)
   return translate(L_unwrap(w))
end

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
   local translated = {}
   print(inspect(c))
   for i,v in ipairs(c.vs) do
	  translated[i] = translate(v)
   end
   return R.concat(translated)
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
-- print(inspect(rigel_out:calcSdfRate(rigel_out))) -- this function spits back the utilization of the module

-- vectorize -> module -> devectorize
-- idea: change the module to a streaming interface by stamping out the module internally wxh times, then reduce internally until utilization is 100%

-- wraps a rigel vectorize and cast
local function vectorize(t, w, h)
   if t:isNamed() and t.generator == 'Handshake' then
	  t = t.params.A
   end
   local input = R.input(R.HS(t))
   
   local vec = R.connect{
	  input = input,
	  toModule = R.HS(
		 R.modules.vectorize{
			type = t,
			H = 1,
			V = w*h
		 }
	  )
   }

   local output = R.connect{
	  input = vec,
	  toModule = R.HS(
		 C.cast(
			R.array2d(t, w*h, 1),
			R.array2d(t, w, h)
		 )
	  )
   }

   return R.defineModule{
	  input = input,
	  output = output
   }
end

-- wraps a rigel devectorize and cast
local function devectorize(t, w, h)
   if t:isNamed() and t.generator == 'Handshake' then
	  t = t.params.A
   end
   local input = R.input(R.HS(R.array2d(t, w, h)))
   
   local cast = R.connect{
	  input = input,
	  toModule = R.HS(
		 C.cast(
			R.array2d(t, w, h),
			R.array2d(t, w*h, 1)
		 )
	  )
   }

   local output = R.connect{
	  input = cast,
	  toModule = R.HS(
		 R.modules.devectorize{
			type = t,
			H = 1,
			V = w*h,
		 }
	  )
   }

   return R.defineModule{
	  input = input,
	  output = output
   }
end

local function changeRate(t, util)
   local arr_t = t.over
   local w = t.size[1]
   local h = t.size[2]

   local input = R.input(R.HS(t))

   local cast = R.connect{
	  input = input,
	  toModule = R.HS(
		 C.cast(R.array2d(arr_t, w, h),
				R.array2d(arr_t, w*h, 1)
		 )
	  )
   }

   local rate = R.connect{
	  input = cast,
	  toModule = R.HS(
		 R.modules.changeRate{
			type = arr_t,
			H = 1,
			inW = w*h,
			outW = w*h * util[1]/util[2]
		 }
	  )
   }

   return R.defineModule{
	  input = input,
	  output = rate
   }
end

-- @todo: do i want to represent this in my higher level language instead as an internal feature (possibly useful too for users) and then translate to rigel instead?
-- converts a module to operate on streams instead of full images
local function streamify(m)
   -- if the input is not an array the module is already streaming
   if m.inputType.kind ~= 'array' then
   	  return m
   end

   local t = m.inputType.over
   local w = m.inputType.size[1]
   local h = m.inputType.size[2]
   
   local stream_in = R.input(R.HS(t))

   local vec_in = R.connect{
	  input = stream_in,
	  toModule = vectorize(t, w, h)
   }

   local vec_out = R.connect{
	  input = vec_in,
	  toModule = R.HS(m)
   }

   local stream_out = R.connect{
	  input = vec_out,
	  toModule = devectorize(t, w, h)
   }

   -- @todo: this should probably only return stream_out
   -- @todo: need to figure out a better way of figuring out what to calcSdfRate on
   -- @todo: this should also return a lambda
   return R.defineModule{
	  input = stream_in,
	  output = stream_out
   }
   -- return vec_out, stream_out
end

-- local dut, stream_out = streamify(translate(m))
-- print(inspect(dut:calcSdfRate(stream_out)))

local reduce_rate = {}
setmetatable(reduce_rate, dispatch_mt)

local function get_name(m)
   if m.kind == 'lambda' then
	  return get_name(m.output)
   elseif m.kind == 'map' then
	  return m.kind
   elseif m.fn then
	  return get_name(m.fn)
   else
	  return m.kind
   end
end

local function transform(m)
   local RS = require 'rigelSimple'
   local R = require 'rigel'
   local output = m

   local function get_utilization(m)
	  return m:calcSdfRate(output)
   end

   return m:visitEach(function(cur, inputs)
		 local util = get_utilization(cur) or { 0, 0 }
		 if cur.kind == 'apply' then
			if util[2] > 1 then
			   local t = inputs[1].type
			   if t:isNamed() and t.generator == 'Handshake' then
				  t = t.params.A
			   end
			   
			   print('util:  ', util[1]..'/'..util[2])
			   print('inType:', t)

			   local function unwrap_handshake(m)
				  if m.kind == 'makeHandshake' then
					 return m.fn
				  else
					 return m
				  end
			   end

			   local function reduce_rate(m, util)
				  local input = RS.connect{
					 input = RS.input(m.inputType),
					 toModule = changeRate(t, util)
				  }

				  m = unwrap_handshake(m)
				  m = m.output.fn

				  -- local input = RS.connect{
				  -- 	 input = RS.input(RS.HS(m.inputType)),
				  -- 	 toModule = devectorize(m.inputType.over, m.W, m.H)
				  -- }

				  local w = m.W
				  local h = m.H
				  local max_reduce = m.W * m.H
				  local parallelism = max_reduce * util[1]/util[2]
				  print(parallelism)

				  
				  m = RS.modules.map{
					 fn = m.fn,
					 size = { parallelism }
				  }

				  local inter = RS.connect{
					 input = input,
					 toModule = RS.HS(m)
				  }

				  -- local output = RS.connect{
				  -- 	 input = inter,
				  -- 	 toModule = changeRate(inter.type.params.A, { util[2], util[1] })
				  -- }

				  local output = RS.connect{
					 input = inter,
					 toModule = vectorize(inter.type.params.A.over, w, h)
				  }

				  return output
			   end
			   
			   return reduce_rate(cur.fn, util)
			else
			   return RS.connect{
				  input = inputs[1],
				  toModule = cur.fn
			   }
			end
		 end
		 
		 -- @todo: this should also return a lambda
		 return cur
   end)
end

local x = L.input(L.uint8())
local c = L.const(L.uint8(), const_val)
local add_c = L.lambda(L.add()(L.concat(x, c)), x)
local r2 = translate(add_c(x))
local r3 = translate(add_c)
local r4 = streamify(translate(add_c))
-- print(inspect(r2:calcSdfRate(r2)))
-- R.harness{ fn = R.HS(translate(m)),
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test", outSize = im_size }

-- local dut, stream_out = streamify(translate(m))
local stream_out = streamify(translate(m))

-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test2", outSize = im_size }

local stream_out = transform(stream_out.output)
stream_out:visitEach(function(cur)
	  print(get_name(cur))
	  print(inspect(cur, {depth = 2}))
	  print(inspect(cur:calcSdfRate(stream_out)))
end)

local input = stream_out.inputs[1].inputs[1].inputs[1].inputs[1].inputs[1]
stream_out = R.defineModule{
   input = input,
   output = stream_out
}

-- R.harness{ fn = stream_out,
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test3", outSize = im_size }

-- print(inspect(dut:calcSdfRate(stream_out)))

local r_m = translate(m)
-- R.harness{ fn = R.HS(r_m),
--            inFile = "box_32_16.raw", inSize = im_size,
--            outFile = "test", outSize = im_size }

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
