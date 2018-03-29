local memoize = require 'memoize'
local L = require 'betelgeuse.lang'
local I = require 'betelgeuse.ir'
local inline = require 'betelgeuse.passes.inline'

local log = require 'log'
local inspect = require 'inspect'

local _VERBOSE = false

local translate = {}
local translate_mt = {
   __call = function(t, m)
      if _VERBOSE then log.trace("translate." .. m.kind) end
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
   return I.array2d(translate(t.t), t.w, t.h)
end
translate.array2d = memoize(translate.array2d)

function translate.fixed(t)
   local n = t.i + t.f
   return I.bit(n)
end
translate.fixed = memoize(translate.fixed)

function translate.tuple(t)
   local translated = {}
   for i, typ in ipairs(t.ts) do
      translated[i] = translate(typ)
   end

   return I.tuple(unpack(translated))
end
translate.tuple = memoize(translate.tuple)

-- @todo: consider wrapping singletons in T[1,1]
function translate.input(i)
   return I.input(translate(i.type))
end
translate.input = memoize(translate.input)

-- @todo: consider wrapping singletons in T[1,1]
function translate.const(c)
   local function convert(v)
      if type(v) == 'table' then
         for i,val in ipairs(v) do
            v[i] = convert(val)
         end
         return v
      else
         -- shift constant left by fractional bits
         return v * 2^c.type.f
      end
   end

   return I.const(translate(c.type), convert(c.v))
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
   return I.concat(unpack(translated))
end
translate.concat = memoize(translate.concat)

function translate.select(a)
   return R.index{
      input = translate(a.v),
      key = a.n-1
   }
end
translate.select = memoize(translate.select)

function translate.add(m)
   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits
   local in_type = L.fixed(int_bits, frac_bits)

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f
   local out_type = m.out_type

   -- we need to do a bit of processing on the input
   local input = I.input(translate(m.in_type))

   -- split up the input tuple
   local in1 = I.select(input, 1)
   local in2 = I.select(input, 2)

   -- align the decimal point and cast to the right size
   local in1_shift = I.apply(I.shift(-(frac_bits - m.in_type.ts[1].f)), in1)
   local in1_trunc = I.apply(I.trunc(in_width), in1_shift)

   local in2_shift = I.apply(I.shift(-(frac_bits - m.in_type.ts[2].f)), in2)
   local in2_trunc = I.apply(I.trunc(in_width), in2_shift)

   -- concatenate aligned inputs
   local concat = I.concat(in1_trunc, in2_trunc)

   -- now we can just sum like an integer
   local output = I.apply(I.add(), concat)

   -- return this new module
   return I.lambda(output, input)
end
translate.add = memoize(translate.add)

function translate.sub(m)
   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits
   local in_type = L.fixed(int_bits, frac_bits)

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f
   local out_type = m.out_type

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
         outType = translate(in_type),
         shift = -(frac_bits - m.in_type.ts[1].f)
      }
   }

   local in2_shift = R.connect{
      input = in2,
      toModule = R.modules.shiftAndCast{
         inType = in2.type,
         outType = translate(in_type),
         shift = -(frac_bits - m.in_type.ts[2].f)
      }
   }

   -- concatenate aligned inputs
   local concat = R.concat{in1_shift, in2_shift}

   -- now we can just sub like an integer
   local output = R.connect{
      input = concat,
      toModule = R.modules.sub{
         inType = translate(in_type),
         outType = translate(out_type),
         async = true
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
   local in_type = L.fixed(int_bits, frac_bits)

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f
   local out_type = m.out_type

   return R.modules.mult{
      inType = translate(in_type),
      outType = translate(out_type)
   }
end
translate.mul = memoize(translate.mul)

function translate.div(m)
   -- @todo: fix for fixed point

   -- figure out what width the inputs need to be
   local int_bits = math.max(m.in_type.ts[1].i, m.in_type.ts[2].i)
   local frac_bits = math.max(m.in_type.ts[1].f, m.in_type.ts[2].f)
   local in_width = int_bits + frac_bits
   local in_type = L.fixed(int_bits, frac_bits)

   -- figure out the output width
   local out_width = m.out_type.i + m.out_type.f
   local out_type = m.out_type

   return R.modules.div{
      inType = translate(in_type),
      outType = translate(out_type)
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
   return I.upsample_x(m.x, m.y, m.in_type.w, m.in_type.h)
end
translate.upsample = memoize(translate.upsample)

function translate.downsample(m)
   return I.downsample_x(m.x, m.y, m.in_type.w, m.in_type.h)
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

function translate.buffer(m)
   return R.buffer{
      type = translate(m.in_type),
      depth = m.size,
   }
end
translate.buffer = memoize(translate.buffer)

function translate.lambda(l)
   return I.lambda(translate(l.f), translate(l.x))
end
translate.lambda = memoize(translate.lambda)

function translate.apply(a)
   -- propagate input/output type back to the module
   a.m.type = a.type -- @todo: remove
   a.m.out_type = a.type
   a.m.in_type = a.v.type

   local m = translate(a.m)
   local v = translate(a.v)

   if m.kind == 'lambda' then
      return inline(m, v)
   else
      return I.apply(m, v)
   end
end
translate.apply = memoize(translate.apply)

function translate.map(m)
   local size = { m.type.w, m.type.h }

   -- propagate type to module applied in map
   m.m.type = m.type.t
   m.m.out_type = m.out_type.t
   m.m.in_type = m.in_type.t

   return I.map_x(translate(m.m), size)
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
