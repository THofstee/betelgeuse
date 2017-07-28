local R = require 'rigelSimple'
local C = require 'examplescommon'
local rtypes = require 'types'
local memoize = require 'memoize'
local L = require 'betelgeuse.lang'

local _VERBOSE = false

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
	  pad = { m.left, m.right, m.bottom, m.top },
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
	  crop = { m.left, m.right, m.bottom, m.top },
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

return translate
