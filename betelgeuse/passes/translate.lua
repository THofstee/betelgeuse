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

function translate.fixed(t)
   if t.s then
      return rtypes.int(t.i + t.f)
   else
      return rtypes.uint(t.i + t.f)
   end
end
translate.fixed = memoize(translate.fixed)

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

function translate.index(a)
   return R.index{
      input = translate(a.v),
      key = a.n-1
   }
end
translate.index = memoize(translate.index)

function translate.add(m)
   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f

   -- we need to do a bit of processing on the input
   local input = R.input(translate(m.in_type))

   -- split up the input tuple
   local in1 = R.index{
      input = input,
      key = 0
   }

   local in2 = R.index{
      input = input,
      key = 1
   }

   -- align the decimal point and cast to the right size
   local in1_shift = R.connect{
      input = in1,
      toModule = R.modules.shiftAndCast{
         inType = in1.type,
         outType = rtypes.uint(in_width),
         shift = -(frac_bits - m.in_type.ts[1].f)
      }
   }

   local in2_shift = R.connect{
      input = in2,
      toModule = R.modules.shiftAndCast{
         inType = in2.type,
         outType = rtypes.uint(in_width),
         shift = -(frac_bits - m.in_type.ts[2].f)
      }
   }

   -- concatenate aligned inputs
   local concat = R.concat{in1_shift, in2_shift}

   -- now we can just sum like an integer
   local output = R.connect{
      input = concat,
      toModule = R.modules.sum{
         inType = rtypes.uint(in_width),
         outType = rtypes.uint(out_width)
      }
   }

   -- return this new module
   return R.defineModule{
      input = input,
      output = output
   }
end
translate.add = memoize(translate.add)

function translate.sub(m)
   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f

   -- we need to do a bit of processing on the input
   local input = R.input(translate(m.in_type))

   -- split up the input tuple
   local in1 = R.index{
      input = input,
      key = 0
   }

   local in2 = R.index{
      input = input,
      key = 1
   }

   -- align the decimal point and cast to the right size
   local in1_shift = R.connect{
      input = in1,
      toModule = R.modules.shiftAndCast{
         inType = in1.type,
         outType = rtypes.uint(in_width),
         shift = -(frac_bits - m.in_type.ts[1].f)
      }
   }

   local in2_shift = R.connect{
      input = in2,
      toModule = R.modules.shiftAndCast{
         inType = in2.type,
         outType = rtypes.uint(in_width),
         shift = -(frac_bits - m.in_type.ts[2].f)
      }
   }

   -- concatenate aligned inputs
   local concat = R.concat{in1_shift, in2_shift}

   -- now we can just sum like an integer
   local output = R.connect{
      input = concat,
      toModule = R.modules.sub{
         inType = rtypes.uint(in_width),
         outType = rtypes.uint(out_width)
      }
   }

   -- return this new module
   return R.defineModule{
      input = input,
      output = output
   }
end
translate.sub = memoize(translate.sub)

function translate.mul(m)
   -- @todo: fix for fixed point

   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f

   return R.modules.mult{
      inType = rtypes.uint(in_width),
      outType = rtypes.uint(out_width)
   }
end
translate.mul = memoize(translate.mul)

function translate.div(m)
   -- @todo: fix for fixed point

   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f

   return R.modules.div{
      inType = rtypes.uint(in_width),
      outType = rtypes.uint(out_width)
   }
end
translate.div = memoize(translate.div)

function translate.shift(m)
   return R.modules.shiftAndCast{
      inType = translate(m.in_type),
      outType = translate(m.out_type),
      shift = m.n
   }
end
translate.shift = memoize(translate.shift)

function translate.trunc(m)
   print(translate(m.in_type), translate(m.out_type))
   return C.cast(
      translate(m.in_type),
      translate(m.out_type)
   )
end
translate.trunc = memoize(translate.trunc)

function translate.reduce(m)
   -- propagate type to module applied in reduce
   m.m.type = m.type
   m.m.in_type = L.tuple(m.out_type, m.out_type)
   m.m.out_type = m.out_type

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
   -- propagate input/output type back to the module
   a.m.type = a.type -- @todo: remove
   a.m.out_type = a.type
   a.m.in_type = a.v.type

   local m = translate(a.m)
   local v = translate(a.v)

   local function cast(src, dst)
      -- print(a.m.in_type, a.v.type)
      if src.kind ~= 'array' then
         return C.cast(
               src,
               dst
            )
      end

      return R.modules.map{
         fn = cast(src.over, dst.over),
         size = src.size
      }
   end

   if v.type ~= m.inputType then
      v = R.connect{
         input = v,
         toModule = cast(v.type, m.inputType)
      }
   end

   return R.connect{
      input = v,
      toModule = m
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
