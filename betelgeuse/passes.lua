--- A set of compilation passes to lower to and optimize Rigel.
-- @module passes
local path_set = false
if not path_set then
   package.path = "./rigel/?.lua;./rigel/src/?.lua;./rigel/examples/?.lua;" .. package.path
   path_set = true
end

-- Disable SDF checking in rigel for now
local rigel = require 'rigel'
rigel.SDF = false

local R = require 'rigelSimple'
local RM = require 'modules'
local C = require 'examplescommon'
local rtypes = require 'types'
local memoize = require 'memoize'
local L = require 'betelgeuse.lang'

-- @todo: remove this after debugging
local inspect = require 'inspect'

function linenum(level)
   return debug.getinfo(level or 2, 'l').currentline
end

local P = {}

P.translate = require 'betelgeuse.passes.translate'

local _VERBOSE = false

local function is_handshake(t)
   if t:isNamed() and t.generator == 'Handshake' then
	  return true
   elseif t.kind == 'tuple' and is_handshake(t.list[1]) then
	  return true
   end
   
   return false
end

local function unwrap_handshake(m)
   if m.kind == 'makeHandshake' then
	  return m.fn
   else
	  return m
   end
end

local function base(m)
   local ignored = {
	  apply = true,
	  makeHandshake = true,
	  liftHandshake = true,
	  liftDecimate = true,
	  waitOnInput = true,
   }

   if m.fn and ignored[m.kind] then
	  return base(m.fn)
   else
	  return m
   end
end

P.base = base

-- @todo: should make this a class method in lang
function reduction_factor(m, in_rate)
   local factor = { in_rate[1], in_rate[2] }

   local function process(t)
	  if t.kind == 'array2d' then
		 process(t.t)
		 factor[2] = factor[2] * t.w * t.h
	  end
   end

   process(L.unwrap(m).x.type)

   local scale = math.min(factor[1], factor[2])
   factor = { factor[1]/scale, factor[2]/scale }

   return factor
end
P.reduction_factor = reduction_factor

local function get_input(m)
   while m.inputs[1] do
	  m = m.inputs[1]
   end
   return m
end
P.get_input = get_input

local function get_name(m)
   if false then
	  return base(m).kind .. '-' .. base(m).name
   end
   
   if m.kind == 'lambda' then
   	  return m.kind .. '(' .. get_name(m.output) .. ')'
   elseif m.name then
   	  if m.fn then
   		 return m.kind .. '_' .. m.name .. '(' .. get_name(m.fn) .. ')'
   	  elseif m.kind == 'input' then
   		 return m.kind .. '_' .. m.name .. '(' .. tostring(m.type) .. ')'
   	  else
   		 return m.name
   	  end
   else
   	  if m.fn then
   		 return m.kind .. '(' .. get_name(m.fn) .. ')'
   	  elseif m.kind == 'input' then
   		 return m.kind .. '(' .. tostring(m.type) .. ')'
   	  else
   		 return m.kind
   	  end
   end
end
P.get_name = get_name

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

-- @todo: split body in to inline_cur and then use inline_cur in other places?
local function inline(m, input)
   return m.output:visitEach(function(cur, inputs)
   		 if cur.kind == 'input' then
   			return input
		 elseif cur.kind == 'apply' then
			return R.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 elseif cur.kind == 'concat' then
			return R.concat(inputs)
		 else
			assert(false, 'inline ' .. cur.kind .. ' not yet implemented')
		 end
   end)
end

-- converts a module to be handshaked
local function to_handshake(m)
   local t_in, w_in, h_in
   if is_handshake(m.inputType) then
	  return m
   end
   
   local hs_in = R.input(R.HS(m.inputType))

   -- inline the top level of the module
   local hs_out = m.output:visitEach(function(cur, inputs)
   		 if cur.kind == 'input' then
   			return hs_in
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
   
   return R.defineModule{
	  input = hs_in,
	  output = hs_out
   }
end
P.to_handshake = to_handshake

-- @todo: maybe this should operate the same way as transform and peephole and case on whether or not the input is a lambda? in any case i think all 3 should be consistent.
-- @todo: do i want to represent this in my higher level language instead as an internal feature (possibly useful too for users) and then translate to rigel instead?
-- converts a module to operate on streams instead of full images
local function streamify(m, elem_rate)
   -- elem rate := { n_pixels, every_m_cycles }
   local elem_rate = elem_rate or { 1, 1 }
   local elem_size = elem_rate[1]
   local elem_rate = { 1, elem_rate[2] }

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

   local stream_in = R.input(R.HS(R.array(t_in, elem_size)), {elem_rate})

   local vec_in = change_rate(stream_in, { w_in, h_in })
   
   local vec_out = inline(to_handshake(m), vec_in)
   
   local stream_out = change_rate(vec_out, { elem_size, 1 })

   return R.defineModule{
	  input = stream_in,
	  output = stream_out
   }
end
P.streamify = streamify

-- @todo: rename function
-- @todo: change to take in max_rate and util instead
local function divisor(n, k)
   -- find the smallest divisor of n greater than k
   for i=k,math.floor(math.sqrt(n)) do
	  if n%i == 0 then
		 return i
	  end
   end

   -- find the greatest divisor of n smaller than k
   for i in k,2,-1 do
	  if n%i == 0 then
		 return i
	  end
   end

   -- couldn't find anything better, return 1
   return 1
end

-- @todo: replace reduce_rate on modules to be reduce_rates on apply
local reduce_rate = {}
local reduce_rate_mt = {
   __call = function(reduce_rate, m, util)
	  -- @todo: this should also make things spit out multiple parallel branches if trying to meet a certain utilization?
	  if util[2] <= util[1] then return m end

	  local dispatch = m.kind
	  if _VERBOSE then print("reduce_rate." .. dispatch) end
	  if string.find(dispatch, 'lift') then return reduce_rate.lift(m, util) end
	  assert(reduce_rate[dispatch], "dispatch function " .. dispatch .. " is nil")
	  return reduce_rate[dispatch](m, util)
   end
}
setmetatable(reduce_rate, reduce_rate_mt)

function reduce_rate.makeHandshake(m, util)
   if string.find(m.fn.fn.kind, 'lift') then return reduce_rate.lift(m, util) end
   return reduce_rate[m.fn.fn.kind](m, util)
end

function reduce_rate.liftHandshake(m, util)
   assert(false, "not yet implemented")
end

function reduce_rate.apply(m, util)
   -- return R.connect{
   -- 	  input = reduce_rate(m.inputs[1]),
   -- 	  toModule = reduce_rate(m)
   -- }
   if string.find(m.fn.kind, 'lift') then return reduce_rate.lift(m, util) end
   return reduce_rate[m.fn.kind](m, util)
end

function reduce_rate.input(m, util)
   if is_handshake(m.type) then
	  return m
   else
	  return R.input(R.HS(m.type))
   end
end

function reduce_rate.concat(m, util)
   local inputs = {}
   for i,input in ipairs(m.inputs) do
	  inputs[i] = reduce_rate(input, util)
   end

   return R.concat(inputs)
end

function reduce_rate.map(m, util)
   local input = reduce_rate(m.inputs[1], util)

   local m = unwrap_handshake(m.fn)
   local t = m.inputType
   local w = m.W
   local h = m.H

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local in_rate = change_rate(input, { par, 1 })

   -- @todo: the module being mapped over probably also needs to be optimized, for example recursive maps
   m = R.modules.map{
	  fn = m.fn,
	  size = { par }
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   return change_rate(inter, { w, h })
end

function reduce_rate.SoAtoAoS(m, util)
   print('@todo: implement', m.kind, linenum())
   local input = reduce_rate(m.inputs[1], util)

   local m = m.fn
   local t = m.inputType

   return R.connect{
	  input = input,
	  toModule = R.HS(m)
   }
end

function reduce_rate.broadcast(m, util)
   assert(false, "Not yet implemented")
   local out_size = m.outputType.size

   local max_reduce = out_size[1]*out_size[2]
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local input = R.input(R.HS(m.inputType))

   local m = C.broadcast(m.inputType, par, 1)
   
   local inter = R.connect{
	  input = input,
	  toModule = R.HS(m)
   }
   
   local output = change_rate(inter, out_size)

   return R.defineModule{
	  input = input,
	  output = output
   }
end

function reduce_rate.lift(m, util)
   -- certain modules need to be reduced, but are implemented as lifts
   if string.find(m.name, 'Broadcast') == 1 then
	  return reduce_rate.broadcast(m, util)
   end

   -- otherwise, don't do anything
   return R.connect{
	  input = reduce_rate(m.inputs[1], util),
	  toModule = R.HS(m.fn)
   }
end

function reduce_rate.pad(m, util)
   local input = reduce_rate(m.inputs[1], util)
   local m = unwrap_handshake(m.fn)

   local t = m.inputType
   local w = m.width
   local h = m.height
   local out_size = m.outputType.size

   local max_reduce = out_size[1]*out_size[2]
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)
      
   local in_rate = change_rate(input, { par, 1 })
   
   local m = R.modules.padSeq{
	  type = m.type,
	  V = par,
	  size = { w, h },
	  pad = { m.L, m.R, m.Top, m.B },
	  value = m.value
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   return change_rate(inter, out_size)
end

function reduce_rate.crop(m, util)
   local input = reduce_rate(m.inputs[1], util)
   
   -- @todo: double check implementation
   local m = unwrap_handshake(m.fn)

   local t = m.inputType
   local w = m.width
   local h = m.height
   local out_size = m.outputType.size

   local max_reduce = w*h
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)
   
   local in_rate = change_rate(input, { par, 1 })
   
   m = R.modules.cropSeq{
	  type = m.type,
	  V = par,
	  size = { w, h },
	  crop = { m.L, m.R, m.Top, m.B }
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   return change_rate(inter, out_size)
end

function reduce_rate.upsample(m, util)
   assert(false, "Not yet implemented")
   -- @todo: change to be upsampleY first then upsampleX, once implemented
   local input = R.input(R.HS(m.inputType))

   -- @todo: divide by util to figure out output element type
   -- @todo: sample for downsample
   local out_size = m.outputType.size
   local par = math.ceil(out_size[1]*out_size[2] * util[1]/util[2])
   local in_size = { m.inputType.size[1], m.inputType.size[2] }

   -- @todo: reduce in x first or in y first?
   -- @todo: hack
   in_size[2] = math.ceil(in_size[2]/util[2])
   in_size[1] = math.ceil(in_size[1]/(util[2]/(m.inputType.size[2]/in_size[2])))
   if par ~= 1 then in_size[1] = m.scaleX*m.scaleY*in_size[1] end

   local in_rate = change_rate(input, in_size)

   -- @todo: this is not scanline order anymore really
   m = R.modules.upsampleSeq{
	  type = m.type,
	  V = par,
	  size = { m.width, m.height },
	  scale = { m.scaleX, m.scaleY }
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

function reduce_rate.downsample(m, util)
   assert(false, "Not yet implemented")
   local input = R.input(R.HS(m.inputType))

   local in_size = m.inputType.size
   local par = math.ceil(in_size[1]*in_size[2] * util[1]/util[2])
   
   local in_rate = change_rate(input, { par, 1 })

   local out_size = m.outputType.size

   if m.scaleY == 1 then
	  m = RM.downsampleXSeq(
		 m.type,
		 m.width,
		 m.height,
		 par,
		 m.scaleX
	  )
   else
	  -- @todo: for some reason this is super slow when scaleY == 1
	  m = R.modules.downsampleSeq{
		 type = m.type,
		 V = par,
		 size = { m.width, m.height },
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

function reduce_rate.stencil(m, util)
   print('@todo: fixme', m.kind, linenum())
   local input = reduce_rate(m.inputs[1], util)

   local m = unwrap_handshake(m.fn)
   
   -- @todo: hack, should move this to translate probably
   -- @todo: total hack, needs extra pad and crop
   m.xmin = m.xmin - m.xmax
   m.xmax = 0
   m.ymin = m.ymin - m.ymax
   m.ymax = 0
   
   local size = { m.w, m.h }

   local par = math.ceil(size[1]*size[2] * util[1]/util[2])
   par = divisor(size[1]*size[2], par)

   local m = R.modules.linebuffer{
	  type = m.inputType.over,
	  V = par,
	  size = size,
	  stencil = { m.xmin, m.xmax, m.ymin, m.ymax }
   }

   local in_rate = change_rate(input, { par, 1 })

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   return change_rate(inter, size)
end

function reduce_rate.packTuple(m, util)
   local input = reduce_rate(m.inputs[1], util)

   local m = unwrap_handshake(m.fn)
   
   local hack = {}
   for i,t in ipairs(m.inputType.list) do
	  hack[i] = t.params.A
   end
	  
   if input.kind == 'concat' then
	  -- @todo: should this introduce changeRates on every input?
	  return R.connect{
		 input = input,
		 toModule = RM.packTuple(hack)
	  }
   else
	  return R.connect{
		 input = input,
		 toModule = RM.packTuple(hack)
	  }
   end
end

function reduce_rate.lambda(m, util)
   assert(false, "Not yet implemented")
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

function reduce_rate.constSeq(m, util)
   print('@todo: implement', m.kind, linenum())

   return m
end

-- @todo: maybe this should only take in a lambda as input
local function transform(m, util)
   local m = to_handshake(m)
   local output
   if m.kind == 'lambda' then
	  output = m.output
   else
	  output = m
   end

   -- run rate optimization
   output = reduce_rate(output, util)
   
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

-- @todo: maybe this should only take in a lambda as input
local function peephole(m)
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
				  return R.connect{
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

		 return R.connect{
			input = inputs[1],
			toModule = cur.fn
		 }
	  elseif cur.kind == 'concat' then
		 return R.concat(inputs)
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

		 return R.connect{
			input = inputs[1],
			toModule = cur.fn
		 }
	  elseif cur.kind == 'concat' then
		 return R.concat(inputs)
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

		 return R.connect{
			input = inputs[1],
			toModule = cur.fn
		 }
	  elseif cur.kind == 'concat' then
		 return R.concat(inputs)
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
	  return R.defineModule{
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
	  if tostring(cur.fn.inputType) == 'null' then
		 return 'nil' .. ' -> ' .. tostring(cur.fn.outputType)
	  else
		 return tostring(cur.fn.inputType) .. ' -> ' .. tostring(cur.fn.outputType)
	  end
   end
end
P.get_type_signature = get_type_signature

local function rates(m)
   m.output:visitEach(function(cur)
		 print(P.get_name(cur))
		 print(':: ' .. P.get_type_signature(cur))
		 -- print(inspect(cur:calcSdfRate(m.output))) -- @todo: replace
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

   -- Remove handshakes on everything as we iterate
   local function removal(cur, inputs)
	  if cur.kind == 'apply' then
		 if needs_hs(base(cur)) then
			-- If something needs a handshake, discard the changes
			return cur
		 elseif inputs[1].type.generator == 'Handshake' then
			-- Something earlier failed, so don't remove handshake here
			return R.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 else
			-- Our input isn't handshaked, so remove handshake if we need to
			if cur.fn.kind == 'makeHandshake' then
			   return R.connect{
				  input = inputs[1],
				  toModule = cur.fn.fn
			   }
			end

			return R.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 end
	  elseif cur.kind == 'input' then
		 -- Start by removing handshake on all inputs
		 if cur.type.generator == 'Handshake' then
			return R.input(cur.type.params.A)
		 end
	  end
	  return cur
   end
   
   if m.kind == 'lambda' then
	  local output = m.output:visitEach(removal)
	  local input = get_input(output)
	  
	  return R.defineModule{
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
