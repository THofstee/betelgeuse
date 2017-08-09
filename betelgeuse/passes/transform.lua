local R = require 'rigelSimple'
local RM = require 'modules'
local C = require 'examplescommon'

local to_handshake = require 'betelgeuse.passes.to_handshake'

local _VERBOSE = false

local function linenum(level)
   return debug.getinfo(level or 2, 'l').currentline
end

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

local function get_input(m)
   while m.inputs[1] do
	  m = m.inputs[1]
   end
   return m
end

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
   
   if input.kind == 'apply' and input.fn.kind == 'packTuple' and input.inputs[1].kind == 'concat' then
	  local size = m.outputType.params.A.size

	  local max_reduce = size[1]*size[2]
	  local par = math.ceil(max_reduce * util[1]/util[2])
	  par = divisor(max_reduce, par)
	  
	  local streams_in = {}
	  local hack = {}
	  local hack2 = {}

	  for i,inpt in ipairs(input.inputs[1].inputs) do
		 streams_in[i] = change_rate(inpt, { par, 1 })
		 hack[i] = streams_in[i].type.params.A
		 hack2[i] = hack[i].over
	  end

	  local inter = R.connect{
		 input = R.concat(streams_in),
		 toModule = RM.packTuple(hack)
	  }

	  local inter2 = R.connect{
		 input = inter,
		 toModule = R.HS(
			R.modules.SoAtoAoS{
			   type = hack2,
			   size = { par, 1 }
			}
		 )
	  }

	  return change_rate(inter2, size)
   end   

   return R.connect{
	  input = input,
	  toModule = R.HS(m)
   }
end

function reduce_rate.broadcast(m, util)
   local input = reduce_rate(m.inputs[1], util)
   local m = unwrap_handshake(m.fn)

   local out_size = m.outputType.size

   local max_reduce = out_size[1]*out_size[2]
   local par = math.ceil(max_reduce * util[1]/util[2])
   par = divisor(max_reduce, par)

   local m = C.broadcast(m.inputType, par, 1)
   
   local inter = R.connect{
	  input = input,
	  toModule = R.HS(m)
   }
   
   return change_rate(inter, out_size)
end

function reduce_rate.lift(m, util)
   -- certain modules need to be reduced, but are implemented as lifts
   if string.find(unwrap_handshake(m.fn).name, 'Broadcast') == 1 then
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
   -- @todo: change to be upsampleY first then upsampleX, once implemented
   local input = reduce_rate(m.inputs[1], util)
   local m = unwrap_handshake(m.fn)

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

   return change_rate(inter, out_size)
end

function reduce_rate.downsample(m, util)
   local input = reduce_rate(m.inputs[1], util)
   local m = unwrap_handshake(m.fn)

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

   return change_rate(inter, out_size)
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

   return R.connect{
	  input = input,
	  toModule = RM.packTuple(hack)
   }
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

return transform
