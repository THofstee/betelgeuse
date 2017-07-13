--- A set of compilation passes to lower to and optimize Rigel.
-- @module passes
package.path = "/home/hofstee/rigel/?.lua;/home/hofstee/rigel/src/?.lua;/home/hofstee/rigel/examples/?.lua;" .. package.path
local R = require 'rigelSimple'
local C = require 'examplescommon'
local rtypes = require 'types'
local memoize = require 'memoize'
local L = require 'lang'
local T = L.raw

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
   return R.array2d(translate(t.t), t.w*t.h, 1)
end
translate.array2d = memoize(translate.array2d)

function translate.array(t)
   return R.array(translate(t.t), t.n)
end
translate.array = memoize(translate.array)

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

function translate.input(i)
   return R.input(translate(i.type))
end
translate.input = memoize(translate.input)

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
	  m.w*m.h
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
	  size = { m.in_type.w*m.in_type.h, 1 }
   }
end
translate.reduce = memoize(translate.reduce)

function translate.pad(m)
   local t = translate(m.type)
   local arr_t = translate(m.type.t)
   local w = m.type.w-m.left-m.right
   local h = m.type.h-m.top-m.bottom
   local pad_w = m.type.w
   local pad_h = m.type.h

   local vec_in = R.input(translate(L.array2d(m.type.t, w, h)))

   local cast_in = R.connect{
	  input = vec_in,
	  toModule = C.cast(
		 R.array2d(arr_t, w*h, 1),
		 R.array2d(arr_t, w, h)
	  )
   }

   local cast_out = R.connect{
	  input = cast_in,
	  toModule = R.modules.pad{
		 type = arr_t,
		 size = { w, h },
		 pad = { m.left, m.right, m.top, m.bottom },
		 value = 0
	  }
   }

   local vec_out = R.connect{
	  input = cast_out,
	  toModule = C.cast(
		 R.array2d(arr_t, pad_w, pad_h),
		 R.array2d(arr_t, pad_w*pad_h, 1)
	  )
   }

   return R.defineModule{
	  input = vec_in,
	  output = vec_out
   }

   -- @todo: remove this, only here so I can remember what to do in reduce_rate
   -- local vec_in = R.input(R.HS(translate(L.array2d(m.type.t, w, h))))

   -- local stream_in = R.connect{
   -- 	  input = vec_in,
   -- 	  toModule = R.HS(R.modules.devectorize{
   -- 						 type = arr_t,
   -- 						 H = 1,
   -- 						 V = w*h
   -- 										   }
   -- 	  )
   -- }

   -- local stream_out = R.connect{
   -- 	  input = stream_in,
   -- 	  toModule = R.HS(R.modules.padSeq{
   -- 						 type = translate(m.type.t),
   -- 						 V = 1,
   -- 						 size = { w, h },
   -- 						 pad = { -m.offset_x, m.extent_x+m.offset_x-1, -m.offset_y, m.extent_y+m.offset_y-1 },
   -- 						 value = 0
   -- 	  })
   -- }

   -- local vec_out = R.connect{
   -- 	  input = stream_out,
   -- 	  toModule = R.HS(R.modules.vectorize{
   -- 						 type = arr_t,
   -- 						 H = 1,
   -- 						 V = pad_w*pad_h
   -- 										 }
   -- 	  )
   -- }

   -- return R.defineModule{
   -- 	  input = vec_in,
   -- 	  output = vec_out
   -- }

   -- -- return R.modules.padSeq{
   -- -- 	  type = translate(m.type.t),
   -- -- 	  V = 1,
   -- -- 	  size = { m.type.w-m.extent_x, m.type.h-m.extent_y },
   -- -- 	  pad = { -m.offset_x, m.extent_x+m.offset_x-1, -m.offset_y, m.extent_y+m.offset_y-1 },
   -- -- 	  value = 0
   -- -- }
end
translate.pad = memoize(translate.pad)

function translate.stencil(m)
   local w = m.type.w
   local h = m.type.h
   local in_elem_t = translate(m.type.t.t)
   local inter_elem_t = R.array2d(in_elem_t, m.type.t.w, m.type.t.h)
   local out_elem_t = translate(m.type.t)

   local vec_in = R.input(R.array2d(in_elem_t, w*h, 1))

   local cast_in = R.connect{
	  input = vec_in,
	  toModule = C.cast(
		 R.array2d(in_elem_t, w*h, 1),
		 R.array2d(in_elem_t, w, h)
	  )
   }

   local cast_out = R.connect{
	  input = cast_in,
	  toModule = C.stencil(
		 in_elem_t,
		 w,
		 h,
		 m.offset_x,
		 m.extent_x+m.offset_x-1,
		 m.offset_y,
		 m.extent_y+m.offset_y-1
	  )
   }

   -- cast inner type
   local vec_out = R.connect{
	  input = cast_out,
	  toModule = C.cast(
		 R.array2d(inter_elem_t, w, h),
		 R.array2d(out_elem_t, w, h)
	  )
   }

   -- cast outer type
   local vec2_out = R.connect{
	  input = vec_out,
	  toModule = C.cast(
		 R.array2d(out_elem_t, w, h),
		 R.array2d(out_elem_t, w*h, 1)
	  )
   }

   return R.defineModule{
	  input = vec_in,
	  output = vec2_out
   }
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
   local size
   if T.array:isclassof(m.type) then
	  size = { m.type.n }
   elseif T.array2d:isclassof(m.type) then
	  size = { m.type.w*m.type.h, 1 }
   end

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
	  size = { m.out_type.w*m.out_type.h, 1 }
   }
end
-- @todo: I think only the values should be memoized.
-- translate.zip = memoize(translate.zip)

P.translate = translate

-- wraps a rigel vectorize
local function vectorize(t, w, h)
   if is_handshake(t) then
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

-- wraps a rigel devectorize
local function devectorize(t, w, h)
   if is_handshake(t) then
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

-- @todo: maybe this should operate the same way as transform and peephole and case on whether or not the input is a lambda? in any case i think all 3 should be consistent.
-- @todo: do i want to represent this in my higher level language instead as an internal feature (possibly useful too for users) and then translate to rigel instead?
-- converts a module to operate on streams instead of full images
local function streamify(m)
   -- if the input is not an array the module is already streaming
   if m.inputType.kind ~= 'array' then
   	  return m
   end

   local t_in = m.inputType.over
   local w_in = m.inputType.size[1]
   local h_in = m.inputType.size[2]
   
   local t_out = m.outputType.over
   local w_out = m.outputType.size[1]
   local h_out = m.outputType.size[2]
   
   local stream_in = R.input(R.HS(t_in))

   local vec_in = R.connect{
	  input = stream_in,
	  toModule = vectorize(t_in, w_in, h_in)
   }

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
			   ),
			   util = vec_in.fn.sdfOutput
			}

			-- @todo: not sure but maybe want to also defineModule here
			return R.connect{
			   input = const,
			   toModule = R.HS(
				  C.cast(
					 R.array2d(cur.type, 1, 1),
					 cur.type
				  )
			   )
			}
   		 end

		 if cur.kind == 'apply' then
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
   
   local stream_out = R.connect{
	  input = vec_out,
	  toModule = devectorize(t_out, w_out, h_out)
   }

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

local reduce_rate = {}
local reduce_rate_mt = {
   __call = function(t, m, util)
	  if _VERBOSE then print("reduce_rate." .. m.kind) end
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

function reduce_rate.map(m, util)
   local t = m.inputType
   local w = m.W
   local h = m.H

   local max_reduce = w*h
   local parallelism = max_reduce * util[1]/util[2]
   
   local input = R.input(R.HS(t))
   
   local in_rate = R.connect{
	  input = input,
	  toModule = change_rate(t, util)
   }
   
   m = R.modules.map{
	  fn = m.fn,
	  size = { parallelism }
   }

   local inter = R.connect{
	  input = in_rate,
	  toModule = R.HS(m)
   }

   local output = R.connect{
	  input = inter,
	  toModule = change_rate(inter.type.params.A, { util[2], util[1] })
   }

   return R.defineModule{
	  input = input,
	  output = output
   }
end
reduce_rate.map = memoize(reduce_rate.map)

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
local function transform(m)
   local RS = require 'rigelSimple'
   local R = require 'rigel'

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
	  local util = get_utilization(cur) or { 0, 0 }
	  if cur.kind == 'apply' then
		 if util[2] > 1 then
			-- local t = inputs[1].type
			-- if is_handshake(t) then
			--    t = t.params.A
			-- end
			
			-- local function reduce_rate(m, util)
			--    local input = RS.connect{
			-- 	  input = inputs[1],
			-- 	  toModule = change_rate(t, util)
			--    }

			--    m = unwrap_handshake(m)
			--    local w = m.W
			--    local h = m.H
			--    m = m.fn

			--    local max_reduce = w*h
			--    local parallelism = max_reduce * util[1]/util[2]
			   
			--    m = RS.modules.map{
			-- 	  fn = m,
			-- 	  size = { parallelism }
			--    }

			--    local inter = RS.connect{
			-- 	  input = input,
			-- 	  toModule = RS.HS(m)
			--    }

			--    local output = RS.connect{
			-- 	  input = inter,
			-- 	  toModule = change_rate(inter.type.params.A, { util[2], util[1] })
			--    }

			--    return output
			-- end
			
			-- return reduce_rate(cur.fn, util)

			-- @todo: inline this
			return RS.connect{
			   input = inputs[1],
			   toModule = reduce_rate(cur.fn, util)
			}
		 else
			return RS.connect{
			   input = inputs[1],
			   toModule = cur.fn
			}
		 end
	  end
	  
	  return cur
   end

   if m.kind == 'lambda' then
	  return RS.defineModule{
		 input = m.input,
		 output = m.output:visitEach(optimize)
	  }
   else
	  return m:visitEach(optimize)
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

   local function fuse_changeRate(cur, inputs)
	  if cur.kind == 'apply' then
		 if base(cur).kind == 'changeRate' then
			if #inputs == 1 and base(inputs[1]).kind == 'changeRate' then
			   local temp_cur = base(cur)
			   local temp_input = base(inputs[1])

			   if(temp_cur.inputRate == temp_input.outputRate) then
				  local input = inputs[1].inputs[1]
				  local t = input.type
				  local util = { temp_input.inputRate, temp_cur.outputRate }

				  return RS.connect{
					 input = input,
					 toModule = change_rate(t, util)
				  }
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
		 if base(cur).kind == 'changeRate' then
			local temp_cur = base(cur)
			if temp_cur.inputRate == temp_cur.outputRate then
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
   
   if m.kind == 'lambda' then
	  local output = m.output:visitEach(fuse_changeRate)
	  output = output:visitEach(removal)
	  return RS.defineModule{
		 input = m.input,
		 output = output
	  }
   else
	  local output = m:visitEach(fuse_changeRate)
	  output = output:visitEach(removal)
	  return output
   end
   
   return 
end
P.peephole = peephole

local function get_input(m)
   while m.inputs[1] do
	  m = m.inputs[1]
   end
   return m
end

local function needs_hs(m)
   local modules = {
	  changeRate = true,
   }

   return modules[m.kind]
end

local function handshakes(m)
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
