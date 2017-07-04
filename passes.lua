--- A set of compilation passes to lower to and optimize Rigel.
-- @module passes
package.path = "/home/hofstee/rigel/?.lua;/home/hofstee/rigel/src/?.lua;/home/hofstee/rigel/examples/?.lua;" .. package.path
local R = require 'rigelSimple'
local rtypes = require 'types'
local memoize = require 'memoize'
local L = require 'lang'
local T = L.raw

-- @todo: remove this after debugging
local inspect = require 'inspect'

local P = {}

local dispatch_mt = {
   __call = function(t, m)
	  return t[m.kind](m)
   end
}

local translate = {}
setmetatable(translate, dispatch_mt)

function translate.wrapped(w)
   return translate(L.unwrap(w))
end

function translate.type(t)
   if T.array2d:isclassof(t) then
	  return R.array2d(translate.type(t.t), t.w*t.h, 1)
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
	  size = { m.type.w*m.type.h, 1 }
   end
   
   return R.modules.map{
	  fn = translate(m.m),
	  size = size
   }
end
translate.map = memoize(translate.map)

P.translate = translate

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

   return R.defineModule{
	  input = input,
	  output = vec
   }
end
P.vectorize = vectorize

-- wraps a rigel devectorize and cast
local function devectorize(t, w, h)
   if t:isNamed() and t.generator == 'Handshake' then
	  t = t.params.A
   end
   local input = R.input(R.HS(R.array2d(t, w, h)))

   local output = R.connect{
	  input = input,
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
P.devectorize = devectorize

local function change_rate(t, util)
   local arr_t = t.over
   local w = t.size[1]
   local h = t.size[2]

   if t:isNamed() and t.generator == 'Handshake' then
   	  t = t.params.A
   end
   local input = R.input(R.HS(R.array2d(arr_t, w, h)))

   local rate = R.connect{
   	  input = input,
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
P.change_rate = change_rate

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
P.streamify = streamify

-- local dut, stream_out = streamify(translate(m))
-- print(inspect(dut:calcSdfRate(stream_out)))

local reduce_rate = {}
setmetatable(reduce_rate, dispatch_mt)
P.reduce_rate = reduce_rate

local function get_name(m)
   if m.kind == 'lambda' then
	  return m.kind .. '(' .. get_name(m.output) .. ')'
   -- elseif m.kind == 'apply' then
   -- 	  return m.kind .. '(' .. get_name(m.fn) .. ',' .. get_name(m.inputs[1]) .. ')'
   elseif m.fn then
	  return m.kind .. '(' .. get_name(m.fn) .. ')'
   elseif m.kind == 'input' then
	  return m.kind .. '(' .. tostring(m.type) .. ')'
   else
	  return m.kind
   end
end
P.get_name = get_name

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
			   
			   local function unwrap_handshake(m)
				  if m.kind == 'makeHandshake' then
					 return m.fn
				  else
					 return m
				  end
			   end

			   local function reduce_rate(m, util)
				  local input = RS.connect{
					 input = inputs[1],
					 toModule = change_rate(t, util)
				  }

				  m = unwrap_handshake(m)
				  m = m.output.fn

				  -- local input = RS.connect{
				  -- 	 input = inptus[1],
				  -- 	 toModule = devectorize(m.inputType.over, m.W, m.H)
				  -- }

				  local w = m.W
				  local h = m.H
				  local max_reduce = m.W * m.H
				  local parallelism = max_reduce * util[1]/util[2]
				  
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
				  -- 	 toModule = change_rate(inter.type.params.A, { util[2], util[1] })
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
P.transform = transform

local function get_base(m)
   if m.kind == 'lambda' then
	  return get_base(m.output)
   elseif m.fn then
	  return get_base(m.fn)
   elseif m.kind == 'input' then
	  return m.kind .. '(' .. tostring(m.type) .. ')'
   else
	  return m.kind
   end
end
P.get_base = get_base

local function base(m)
   if m.kind == 'lambda' then
	  return base(m.output)
   elseif m.fn then
	  return base(m.fn)
   else
	  return m
   end
end

P.base = base

local function peephole(m)
   return m:visitEach(function(cur, inputs)
		 if get_base(cur) == 'changeRate' then
			if #inputs == 1 and get_base(inputs[1]) == 'changeRate' then
			   local temp_cur = cur
			   local temp_input = inputs[1]
			   local apply_cur = nil
			   local apply_input = nil

			   while(temp_cur.kind ~= 'changeRate') do
				  apply_cur = temp_cur
				  temp_cur = base(temp_cur)
			   end
			   while(temp_input.kind ~= 'changeRate') do
				  apply_input = temp_input
				  temp_input = base(temp_input)
			   end

			   print(temp_input.inputRate, temp_input.outputRate)
			   print(temp_cur.inputRate, temp_cur.outputRate)

			   if(temp_cur.inputRate == temp_input.outputRate) then
				  -- return a change_rate from temp_input.inputRate to temp_cur.outputRate
			   end

			   print(inspect(temp_cur, {depth = 1}))
			   print(inspect(temp_input, {depth = 1}))
			end
		 end
		 return cur
   end)
end

P.peephole = peephole

return P
