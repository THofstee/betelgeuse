--- A set of compilation passes to lower to and optimize Rigel.
-- @module passes
local path_set = false
if not path_set then
   package.path = package.path .. ';' .. "./rigel/?.lua;./rigel/src/?.lua;./rigel/examples/?.lua;"
   path_set = true
end

local R = require 'rigelSimple'
local RM = require 'modules'
local C = require 'examplescommon'
local rtypes = require 'types'
local memoize = require 'memoize'
local L = require 'lang'

-- @todo: remove this after debugging
local inspect = require 'inspect'

local P = {}

local _VERBOSE = _VERBOSE or false

local function is_handshake(t)
   if t:isNamed() and t.generator == 'Handshake' then
	  return true
   elseif t.kind == 'tuple' and is_handshake(t.list[1]) then
	  return true
   end
   
   return false
end

local translate = {}
local translate_mt = {
   __call = function(t, m)
	  if _VERBOSE then print("translate." .. m.kind) end
	  assert(t[m.kind], "dispatch function " .. m.kind .. " is nil")
	  return t[m.kind](m)
   end
}
setmetatable(translate, translate_mt)

function translate.wrapped(w)
   return translate(L.unwrap(w))
end
translate.wrapped = memoize(translate.wrapped)

function translate.array2d(t)
   return R.array2d(translate(t.t), t.w, t.h)
end
translate.array2d = memoize(translate.array2d)

function translate.uint(t)
   return rtypes.uint(t.n)
end
translate.uint = memoize(translate.uint)

function translate.tuple(t)
   local translated = {}
   for i, typ in ipairs(t.ts) do
	  translated[i] = translate(typ)
   end
   
   return R.tuple(translated)
end
translate.tuple = memoize(translate.tuple)

-- @todo: consider wrapping singletons in T[1,1]
function translate.input(i)
   return R.input(translate(i.type))
end
translate.input = memoize(translate.input)

-- @todo: consider wrapping singletons in T[1,1]
function translate.const(c)
   -- Flatten an n*m table into a 1*(n*m) table
   local function flatten_mat(m)
	  if type(m) == 'number' then
		 return m
	  end
	  
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

   return R.constant{
	  type = translate(c.type),
	  value = flatten_mat(c.v)
   }
end
translate.const = memoize(translate.const)

function translate.broadcast(m)
   return C.broadcast(
	  translate(m.type.t),
	  m.w,
	  m.h
   )
end
translate.broadcast = memoize(translate.broadcast)

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

function translate.mul(m)
   return R.modules.mult{
	  inType = R.uint8,
	  outType = R.uint8
   }
end
translate.add = memoize(translate.add)

function translate.reduce(m)
   return R.modules.reduce{
	  fn = translate(m.m),
	  size = { m.in_type.w, m.in_type.h }
   }
end
translate.reduce = memoize(translate.reduce)

function translate.pad(m)
   local arr_t = translate(m.type.t)
   local w = m.type.w-m.left-m.right
   local h = m.type.h-m.top-m.bottom

   return R.modules.pad{
	  type = arr_t,
	  size = { w, h },
	  pad = { m.left, m.right, m.top, m.bottom },
	  value = 0
   }
end
translate.pad = memoize(translate.pad)

function translate.crop(m)
   local arr_t = translate(m.type.t)
   local w = m.type.w+m.left+m.right
   local h = m.type.h+m.top+m.bottom

   return R.modules.crop{
	  type = arr_t,
	  size = { w, h },
	  crop = { m.left, m.right, m.top, m.bottom },
	  value = 0
   }
end
translate.crop = memoize(translate.crop)

function translate.upsample(m)
   return R.modules.upsample{
	  type = translate(m.in_type.t),
	  size = { m.in_type.w, m.in_type.h },
	  scale = { m.x, m.y }
   }
end
translate.upsample = memoize(translate.upsample)

function translate.downsample(m)
   return R.modules.downsample{
	  type = translate(m.in_type.t),
	  size = { m.in_type.w, m.in_type.h },
	  scale = { m.x, m.y }
   }
end
translate.downsample = memoize(translate.downsample)

function translate.stencil(m)
   local w = m.type.w
   local h = m.type.h
   local in_elem_t = translate(m.type.t.t)

   return  C.stencil(
	  in_elem_t,
	  w,
	  h,
	  m.offset_x,
	  m.extent_x+m.offset_x-1,
	  m.offset_y,
	  m.extent_y+m.offset_y-1
   )
end
translate.stencil = memoize(translate.stencil)

function translate.apply(a)
   -- propagate output type back to the module
   a.m.type = a.type
   a.m.out_type = a.type
   a.m.in_type = a.v.type

   return R.connect{
	  input = translate(a.v),
	  toModule = translate(a.m)
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
   local size = { m.type.w, m.type.h }
   
   -- propagate type to module applied in map
   m.m.type = m.type.t
   m.m.out_type = m.out_type.t
   m.m.in_type = m.in_type.t
   
   return R.modules.map{
	  fn = translate(m.m),
	  size = size
   }
end
translate.map = memoize(translate.map)

function translate.zip(m)
   return R.modules.SoAtoAoS{
	  type = translate(m.out_type.t).list,
	  size = { m.out_type.w, m.out_type.h }
   }
end
-- @todo: I think only the values should be memoized.
-- translate.zip = memoize(translate.zip)

P.translate = translate

function reduction_factor(m, in_elem_size)
   local factor = { 1, 1 }

   local function process(t)
	  if t.kind == 'array2d' then
		 process(t.t)
		 factor[2] = factor[2] * t.w * t.h
	  end
   end

   process(L.unwrap(m).x.type)

   return factor
end
P.reduction_factor = reduction_factor

local function change_rate(input, out_size)
   local t = input.type
   if is_handshake(t) then
   	  t = t.params.A
   end

   local arr_t, w, h
   if t:isArray() then
	  arr_t = t.over
	  w = t.size[1]
	  h = t.size[2]
   else
	  arr_t = t
	  w = 1
	  h = 1
   end

   local in_cast = R.connect{
	  input = input,
	  toModule = R.HS(
		 C.cast(
			R.array2d(arr_t, w, h),
			R.array2d(arr_t, w*h, 1)
		 )
	  )
   }

   local w_out = out_size[1]
   local h_out = out_size[2]

   local rate = R.connect{
   	  input = in_cast,
   	  toModule = R.HS(
   		 R.modules.changeRate{
   			type = arr_t,
   			H = 1,
   			inW = w*h,
   			outW = w_out*h_out
   		 }
   	  )
   }

   local output = R.connect{
	  input = rate,
	  toModule = R.HS(
		 C.cast(
			R.array2d(arr_t, w_out*h_out, 1),
			R.array2d(arr_t, w_out, h_out)
		 )
	  )
   }

   return output
end
P.change_rate = change_rate

-- @todo: maybe this should operate the same way as transform and peephole and case on whether or not the input is a lambda? in any case i think all 3 should be consistent.
-- @todo: do i want to represent this in my higher level language instead as an internal feature (possibly useful too for users) and then translate to rigel instead?
-- converts a module to operate on streams instead of full images
local function streamify(m, elem_size)
   local elem_size = elem_size or 1

   local t_in, w_in, h_in
   if is_handshake(m.inputType) then
	  if m.inputType.params.A.kind ~= 'array' then return m end
	  t_in = m.inputType.params.A.over
	  w_in = m.inputType.params.A.size[1]
	  h_in = m.inputType.params.A.size[2]
   else
	  if m.inputType.kind ~= 'array' then return m end
	  t_in = m.inputType.over
	  w_in = m.inputType.size[1]
	  h_in = m.inputType.size[2]
   end
   
   local t_out, w_out, h_out
   if is_handshake(m.outputType) then
	  t_out = m.outputType.params.A.over
	  w_out = m.outputType.params.A.size[1]
	  h_out = m.outputType.params.A.size[2]
   else
	  t_out = m.outputType.over
	  w_out = m.outputType.size[1]
	  h_out = m.outputType.size[2]
   end
   
   local stream_in = R.input(R.HS(R.array(t_in, elem_size)))

   local vec_in = change_rate(stream_in, { w_in, h_in })

   -- inline the top level of the module
   local vec_out = m.output:visitEach(function(cur, inputs)
   		 if cur.kind == 'input' then
   			return vec_in
   		 elseif cur.kind == 'constant' then
			-- @todo: this is sort of hacky... convert to HS constseq shift by 0
			local const = R.connect{
			   input = nil,
			   toModule = R.HS(
				  R.modules.constSeq{
					 type = R.array2d(cur.type, 1, 1),
					 P = 1,
					 value = { cur.value }
				  }
			   )
			}

			return R.connect{
			   input = const,
			   toModule = R.HS(
				  C.cast(
					 R.array2d(cur.type, 1, 1),
					 cur.type
				  )
			   )
			}
		 elseif cur.kind == 'apply' then
			if inputs[1].type.kind == 'tuple' then
			   return R.connect{
				  input = R.fanIn(inputs[1].inputs),
				  toModule = R.HS(cur.fn)
			   }
			else
			   return R.connect{
				  input = inputs[1],
				  toModule = R.HS(cur.fn)
			   }
			end
		 elseif cur.kind == 'concat' then
			return R.concat(inputs)
		 end
   end)
   
   local stream_out = change_rate(vec_out, { elem_size, 1 })

   return R.defineModule{
	  input = stream_in,
	  output = stream_out
   }
end
P.streamify = streamify

local function unwrap_handshake(m)
   if m.kind == 'makeHandshake' then
	  return m.fn
   else
	  return m
   end
end

-- @todo: should plug in the semi-constructed input to the prior output to get a more accurate utilization value at each stage of the pipeline?
local reduce_rate = {}
local reduce_rate_mt = {
   __call = function(t, m, util)
	  if _VERBOSE then print("reduce_rate." .. m.kind) end
	  if string.find(m.kind, 'lift') then return t.lift(m, util) end
	  assert(t[m.kind], "dispatch function " .. m.kind .. " is nil")
	  return t[m.kind](m, util)
   end
}
setmetatable(reduce_rate, reduce_rate_mt)
-- reduce_rate = memoize(reduce_rate)

function reduce_rate.makeHandshake(m, util)
   return reduce_rate(unwrap_handshake(m), util)
end
reduce_rate.makeHandshake = memoize(reduce_rate.makeHandshake)

function reduce_rate.liftHandshake(m, util)
   assert(false, "Not yet implemented")
end
reduce_rate.liftHandshake = memoize(reduce_rate.liftHandshake)

function reduce_rate.map(m, util)
   local t = m.inputType
   local w = m.W
   local h = m.H

   local max_reduce = w*h
   -- @todo: should this be floor or ceil?
   local parallelism = math.max(1, math.floor(max_reduce * util[1]/util[2]))

   local input = R.input(R.HS(t))
   
   local in_rate = change_rate(input, { parallelism, 1 })

   -- @todo: the module being mapped over probably also needs to be optimized, for example recursive maps
   m = R.modules.map{
	  fn = m.fn,
	  size = { parallelism }
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   local output = change_rate(inter, { w, h })

   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.map = memoize(reduce_rate.map)

function reduce_rate.SoAtoAoS(m, util)
   -- @todo: implement
   local t = m.inputType

   local input = R.input(R.HS(t))

   local output = R.connect{
	  input = input,
	  toModule = R.HS(m)
   }
   
   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.SoAtoAoS = memoize(reduce_rate.SoAtoAoS)

function reduce_rate.lift(m, util)
   -- @todo: not sure if there's much to do here, think about it
   local m = R.HS(m)
   
   local input = R.input(m.inputType)

   local output = R.connect{
	  input = input,
	  toModule = m
   }
   
   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.lift = memoize(reduce_rate.lift)

function reduce_rate.pad(m, util)
   local t = m.inputType
   local w = m.width
   local h = m.height
   local out_size = m.outputType.size

   local max_reduce = w*h
   local parallelism = max_reduce * util[1]/util[2]
   
   local input = R.input(R.HS(t))
   
   local in_rate = change_rate(input, { parallelism, 1 })
   
   m = R.modules.padSeq{
	  type = m.type,
	  V = parallelism,
	  size = { w, h },
	  pad = { m.L, m.R, m.Top, m.B },
	  value = m.value
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   local output = change_rate(inter, out_size)

   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.pad = memoize(reduce_rate.pad)

function reduce_rate.crop(m, util)
   -- @todo: double check implementation
   local t = m.inputType
   local w = m.width
   local h = m.height
   local out_size = m.outputType.size

   local max_reduce = w*h
   -- @todo: floor or ceil?
   local parallelism = math.floor(max_reduce * util[1]/util[2])
   
   local input = R.input(R.HS(t))
   
   local in_rate = change_rate(input, { parallelism, 1 })
   
   m = R.modules.cropSeq{
	  type = m.type,
	  V = parallelism,
	  size = { w, h },
	  crop = { m.L, m.R, m.Top, m.B }
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   local output = change_rate(inter, out_size)

   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.crop = memoize(reduce_rate.crop)

function reduce_rate.upsample(m, util)
   -- @todo: change to be upsampleY first then upsampleX, once implemented
   local input = R.input(R.HS(m.inputType))

   -- @todo: divide by util to figure out input element type
   -- @todo: sample for downsample
   local in_size = m.inputType.size

   local in_rate = change_rate(input, { 1, 1 })

   -- @todo: divide by util to figure out output element type
   -- @todo: sample for downsample
   local out_size = m.outputType.size

   local par = out_size[1]*out_size[2] * util[1]/util[2]

   -- @todo: this is not scanline order anymore really
   if par == 1 then
	  m = R.modules.upsampleSeq{
		 type = m.type, -- A
		 V = out_size[1]*out_size[2] * util[1]/util[2], -- T
		 size = { m.width, m.height },
		 scale = { m.scaleX, m.scaleY }
	  }
   else
	  m = R.modules.upsample{
		 type = m.type,
		 size = { 1, 1 },
		 scale = { m.scaleX, m.scaleY }
	  }
   end
   
   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   local output = change_rate(inter, out_size)

   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.upsample = memoize(reduce_rate.upsample)

function reduce_rate.downsample(m, util)
   local input = R.input(R.HS(m.inputType))

   local in_size = m.inputType.size
   local par = in_size[1]*in_size[2] * util[1]/util[2]
   
   local in_rate = change_rate(input, { par, 1 })

   local out_size = m.outputType.size

   -- @todo: this is not scanline order anymore really
   if par == 1 then
	  m = R.modules.downsampleSeq{
		 type = m.type,
		 V = 1,
		 size = { m.width, m.height },
		 scale = { m.scaleX, m.scaleY }
	  }
   else
	  m = R.modules.downsample{
		 type = m.type,
		 size = { par, 1 },
		 scale = { m.scaleX, m.scaleY }
	  }
   end
   
   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   local output = change_rate(inter, out_size)

   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.downsample = memoize(reduce_rate.downsample)

function reduce_rate.stencil(m, util)
   -- @todo: implement

   -- @todo: hack, should move this to translate probably
   m.xmin = m.xmin - m.xmax
   m.xmax = 0
   m.ymin = m.ymin - m.ymax
   m.ymax = 0

   local size = { m.w, m.h }

   local m2 = R.modules.linebuffer{
	  type = m.inputType.over,
	  V = 1,
	  size = size,
	  stencil = { m.xmin, m.xmax, m.ymin, m.ymax }
   }
   
   local m = R.HS(m)
   local m2 = R.HS(m2)

   local input = R.input(m.inputType)

   local in_rate = change_rate(input, { 1, 1 })

   local inter = R.connect{
	  input = in_rate,
	  toModule = m2
   }

   local output = change_rate(inter, size)

   -- local output = R.connect{
   -- 	  input = input,
   -- 	  toModule = m
   -- }
   
   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.stencil = memoize(reduce_rate.stencil)

function reduce_rate.packTuple(m, util)
   local input = R.input(m.inputType, {{ 1, 1 }, { 1, 1 }})

   local hack = {}
   for i,t in ipairs(m.inputType.list) do
	  hack[i] = t.params.A
   end
   
   local output = R.connect{
	  input = input,
	  toModule = RM.packTuple(hack)
   }
   
   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.packTuple = memoize(reduce_rate.packTuple)

function reduce_rate.lambda(m, util)
   -- @todo: recurse optimization calls here?
   local m = R.HS(m)
   
   local input = R.input(m.inputType)

   local output = R.connect{
	  input = input,
	  toModule = m
   }
   
   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.lambda = memoize(reduce_rate.lambda)

function reduce_rate.constSeq(m, util)
   -- @todo: implement
   local m = R.HS(m)

   local input = R.input(m.inputType)

   local output = R.connect{
	  input = input,
	  toModule = m
   }
   
   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.constSeq = memoize(reduce_rate.constSeq)

local function get_input(m)
   while m.inputs[1] do
	  m = m.inputs[1]
   end
   return m
end
P.get_input = get_input

local function get_name(m)
   if m.kind == 'lambda' then
	  return m.kind .. '(' .. get_name(m.output) .. ')'
   elseif m.fn then
	  return m.kind .. '(' .. get_name(m.fn) .. ')'
   elseif m.kind == 'input' then
	  return m.kind .. '(' .. tostring(m.type) .. ')'
   elseif m.name then
	  return m.kind .. '_' .. m.name
   else
	  return m.kind
   end
end
P.get_name = get_name

-- @todo: maybe this should only take in a lambda as input
local function transform(m, util)
   local output
   if m.kind == 'lambda' then
	  output = m.output
   else
	  output = m
   end

   local function get_utilization(m)
	  return m:calcSdfRate(output)
   end

   local function optimize(cur, inputs)
	  local util = util or get_utilization(cur) or { 0, 0 }
	  if cur.kind == 'apply' then
		 if util[2] > util[1] then
			local module_in = inputs[1]
			local m = reduce_rate(cur.fn, util)

			-- inline the reduced rate module
			return m.output:visitEach(function(cur, inputs)
				  if cur.kind == 'input' then
					 return module_in
				  elseif cur.kind == 'apply' then
					 return R.connect{
						input = inputs[1],
						toModule = cur.fn
					 }					 
				  elseif cur.kind == 'concat' then
					 return R.concat(inputs)
				  end
			end)
		 else
			return R.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 end
	  elseif cur.kind == 'concat' then
		 return R.concat(inputs)
	  elseif cur.kind == 'input' then
		 if is_handshake(cur.type) then
			return cur
		 else
			return R.input(R.HS(cur.type))
		 end
	  end

	  return cur
   end

   -- run rate optimization
   output = output:visitEach(optimize)
   
   if m.kind == 'lambda' then
	  return R.defineModule{
		 input = get_input(output),
		 output = output
	  }
   else
	  return output
   end   
end
P.transform = transform

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

-- @todo: maybe this should only take in a lambda as input
local function peephole(m)
   local RS = require 'rigelSimple'
   local R = require 'rigel'

   local function fuse_cast(cur, inputs)
	  if cur.kind == 'apply' then
		 if string.find(base(cur).kind, 'cast') then
			local temp_cur = base(cur)
			
			if #inputs == 1 and string.find(base(inputs[1]).kind, 'cast') then
			   local temp_input = base(inputs[1])
			   
			   if temp_input.inputType == temp_cur.outputType then
				  -- eliminate inverse pairs
				  return inputs[1].inputs[1]
			   else
				  -- fuse casts
				  return RS.connect{
					 input = inputs[1].inputs[1],
					 toModule = R.HS(
						C.cast(
						   temp_input.inputType,
						   temp_cur.outputType
						)
					 )
				  }
			   end
			elseif temp_cur.inputType == temp_cur.outputType then
			   -- remove redundant casts
			   return inputs[1]
			end
		 end

		 return RS.connect{
			input = inputs[1],
			toModule = cur.fn
		 }
	  end

	  return cur
   end

   local function fuse_changeRate(cur, inputs)
	  if cur.kind == 'apply' then
		 if base(cur).kind == 'changeRate' then
			if #inputs == 1 and base(inputs[1]).kind == 'changeRate' then
			   local temp_cur = base(cur)
			   local temp_input = base(inputs[1])

			   if(temp_cur.inputRate == temp_input.outputRate) then
				  local input = inputs[1].inputs[1]
				  local size = temp_cur.outputType.params.A.size

				  return change_rate(input, size)
			   end
			end
		 end

		 return RS.connect{
			input = inputs[1],
			toModule = cur.fn
		 }
	  end

	  return cur
   end

   local function removal(cur, inputs)
	  if cur.kind == 'apply' then
		 local temp_cur = base(cur)
		 if temp_cur.kind == 'changeRate' then
			if temp_cur.inputRate == temp_cur.outputRate then
			   return inputs[1]
			end
		 elseif string.find(temp_cur.kind, 'cast') then
			if temp_cur.inputType == temp_cur.outputType then
			   return inputs[1]
			end
		 end

		 return RS.connect{
			input = inputs[1],
			toModule = cur.fn
		 }
	  end

	  return cur
   end

   local output
   if m.kind == 'lambda' then
	  output = m.output
   else
	  output = m
   end

   output = output:visitEach(fuse_cast)
   output = output:visitEach(fuse_changeRate)
   output = output:visitEach(removal)

   if m.kind == 'lambda' then
	  return RS.defineModule{
		 input = m.input,
		 output = output
	  }
   else
	  return output
   end
end
P.peephole = peephole

local function get_type_signature(cur)
   if cur.kind == 'input' or cur.kind == 'constant' then
	  return 'nil' .. ' -> ' .. tostring(cur.type)
   elseif cur.kind == 'concat' then
	  local input = '{'
	  for i,t in ipairs(cur.inputs) do
		 input = input .. tostring(t.type) .. ', '
	  end
	  input = string.sub(input, 1, -3) .. '}'
	  return input .. ' -> ' .. tostring(cur.type)
   else
	  return tostring(cur.fn.inputType) .. ' -> ' .. tostring(cur.fn.outputType)
   end
end
P.get_type_signature = get_type_signature

local function rates(m)
   m.output:visitEach(function(cur)
		 print(P.get_name(cur))
		 print(':: ' .. P.get_type_signature(cur))
		 print(inspect(cur:calcSdfRate(m.output)))
   end)
end
P.rates = rates

local function needs_hs(m)
   local modules = {
	  changeRate = true,
   }

   return modules[m.kind]
end

local function handshakes(m)
   -- @todo: this function shouldn't crash if it can't remove HS, it should just return the original pipeline. need to add another case in cur.kind i think
   local RS = require 'rigelSimple'
   local R = require 'rigel'

   -- Remove handshakes on everything as we iterate
   local function removal(cur, inputs)
	  if cur.kind == 'apply' then
		 if needs_hs(base(cur)) then
			-- If something needs a handshake, discard the changes
			return cur
		 elseif inputs[1].type.generator == 'Handshake' then
			-- Something earlier failed, so don't remove handshake here
			return RS.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 else
			-- Our input isn't handshaked, so remove handshake if we need to
			if cur.fn.kind == 'makeHandshake' then
			   return RS.connect{
				  input = inputs[1],
				  toModule = cur.fn.fn
			   }
			end

			return RS.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 end
	  elseif cur.kind == 'input' then
		 -- Start by removing handshake on all inputs
		 if cur.type.generator == 'Handshake' then
			return RS.input(cur.type.params.A)
		 end
	  end
	  return cur
   end
   
   if m.kind == 'lambda' then
	  local output = m.output:visitEach(removal)
	  local input = get_input(output)
	  
	  return RS.defineModule{
		 input = input,
		 output = output
	  }
   else
	  local output = m:visitEach(removal)
	  return output
   end
   
   return 
end
P.handshakes = handshakes

function P.debug(r)
   -- local Graphviz = require 'graphviz'
   -- local dot = Graphviz()

   -- local function str(s)
   -- 	  return "\"" .. tostring(s) .. "\""
   -- end

   -- local options = {
   -- 	  depth = 2,
   -- 	  process = function(item, path)
   -- 		 if(item == 'loc') then
   -- 			return nil
   -- 		 end
   -- 		 return item
   -- 	  end
   -- }
   
   -- local verbose = true
   -- local a = {}
   -- setmetatable(a, dispatch_mt)

   -- function a.input(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, r.kind .. '(' .. tostring(r.type) .. ')')
   -- 	  return ident
   -- end

   -- function a.apply(r)
   -- 	  local ident = str(r)

   -- 	  if verbose then	   
   -- 		 dot:node(ident, "apply")
   -- 		 dot:edge(a(r.fn), ident)
   -- 		 dot:edge(a(r.inputs[1]), ident)
   -- 	  else
   -- 		 dot:edge(a(r.inputs[1]), a(r.fn))
   -- 	  end
   
   -- 	  return ident
   -- end

   -- function a.liftHandshake(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "liftHandshake")
   -- 	  dot:edge(a(r.fn), ident)
   -- 	  return ident
   -- end

   -- function a.changeRate(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "changeRate[" .. r.inputRate .. "->" .. r.outputRate .. "]")
   -- 	  return ident
   -- end

   -- function a.waitOnInput(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "waitOnInput")
   -- 	  dot:edge(a(r.fn), ident)
   -- 	  return ident
   -- end

   -- function a.map(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "map")
   -- 	  return ident
   -- end

   -- a["lift_slice_typeuint8[1,1]_xl0_xh0_yl0_yh0"] = function(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "lift_slice_typeuint8[1,1]_xl0_xh0_yl0_yh0")
   -- 	  return ident
   -- end

   -- function a.concatArray2d(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "concatArray2d")
   -- 	  return ident
   -- end
   
   -- function a.makeHandshake(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, "makeHandshake")
   -- 	  dot:edge(a(r.fn), ident)
   -- 	  return ident
   -- end

   -- function a.fn(r)
   -- 	  local ident = str(r)
   -- 	  dot:edge(ident, "fn")
   -- 	  return ident
   -- end

   -- function a.lambda(r)
   -- 	  local ident = str(r)
   -- 	  dot:node(ident, r.kind)
   -- 	  dot:edge(a(r.input), ident)
   -- 	  dot:edge(a(r.output), ident)
   -- 	  return ident
   -- end

   -- a(r)
   -- dot:write('dbg/graph.dot')
   -- dot:compile('dbg/graph.dot', 'png')
   
   -- -- print(inspect(r, options))
   -- -- dot:render('dbg/graph.dot', 'png')
end

function P.import()
   local reserved = {
	  import = true,
	  debug = true,
   }
   
   for name, fun in pairs(P) do
	  if not reserved[name] then
		 rawset(_G, name, fun)
	  end
   end
end

return P
