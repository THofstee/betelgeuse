local R = require 'rigelSimple'
local rtypes = require 'types'
local C = require 'examplescommon'
local RM = require 'modules'

local inspect = require 'inspect'
local memoize = require 'memoize'
local log = require 'log'

local _VERBOSE = true

-- local function flatten(t)
--    local res = {}
--    for _,v in ipairs(t) do
--       print(v)
--    end
-- end

local function change_rate(t, out_size)
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

   local input = R.input(R.HS(t))

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

   return R.defineModule{
      input = input,
      output = output
   }
end

local translate = {}
local translate_mt = {
   __call = memoize(function(translate, m)
         local dispatch = m.kind
         assert(translate[dispatch], "dispatch function " .. dispatch .. " is nil")
         return translate[dispatch](m)
   end)
}
setmetatable(translate, translate_mt)

function translate.bit(t)
   return rtypes.int(math.ceil(t.n/8)*8)
end

function translate.array2d(t)
   return R.array2d(translate(t.t), t.w, t.h)
end

function translate.tuple(t)
   local translated = {}
   for i, typ in ipairs(t.ts) do
      translated[i] = translate(typ)
   end

   return R.tuple(translated)
end

function translate.input(x)
   return R.input(R.HS(translate(x.type)))
end

function translate.const(x)
   -- print(inspect(x, {depth = 2}))
   -- return R.modules.constSeq{
   --    type = R.array2d(translate(x.type), 1, 1),
   --    P = 1,
   --    value = { flatten(x.v) },
   -- }
   local m = R.modules.constSeq{
      type = R.array2d(translate(x.type), 1, 1),
      P = 1,
      value = { x.v },
   }

   return R.connect{
      input = nil,
      toModule = R.HS(m)
   }
end

function translate.add(m)
   return R.HS(
      R.modules.sum{
         inType = translate(m.type_in.ts[1]),
         outType = translate(m.type_out),
         async = true
      }
   )
end

function translate.trunc(m)
   -- @todo: is there another way of doing this?
   return R.HS(
      R.modules.shiftAndCast{
         inType = translate(m.type_in),
         outType = translate(m.type_out),
         shift = 0
      }
   )
end

function translate.shift(m)
   return R.HS(
      R.modules.shiftAndCast{
         inType = translate(m.type_in),
         outType = translate(m.type_out),
         shift = m.n,
      }
   )
end

function translate.upsample_x(m)
   -- print(inspect(m, {depth = 2}))
   return R.HS(
      R.modules.upsampleSeq{
         type = translate(m.type_in.t),
         V = 1, -- @todo: is this correct?
         size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
         scale = { m.x, m.y },
      }
   )
end

function translate.downsample_x(m)
   -- print(inspect(m, {depth = 2}))
   return R.HS(
      R.modules.downsampleSeq{
         type = translate(m.type_in.t),
         V = 1, -- @todo: is this correct?
         size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
         scale = { m.x, m.y },
      }
   )
end

function translate.map_x(m)
   -- @todo: the translated module is handshaked, but we only want to handshake around the map instead of the internal modules too...
   -- print(inspect(translate(m.m), {depth = 2}))
   -- print(inspect(m.size))
   -- return R.modules.map{
   --    fn = translate(m.m),
   --    size = m.size,
   -- }
   return translate(m.m)
end

function translate.map_t(m)
   return translate(m.m)
end

function translate.partition(m)
   -- @todo: this is weird
   return change_rate(translate(m.type_in), { 1, 1 })
end

function translate.flatten(m)
   -- @todo: this is weird with the input type...
   return change_rate(translate(m.type_in.t), { m.type_out.w, m.type_out.h })
end

function translate.apply(x)
   -- local v = translate(x.v)
   -- local m = translate(x.m)
   -- print('================')
   -- print('================')
   -- print('================')
   -- print('================')
   -- print(inspect(v, {depth = 2}))
   -- print(inspect(m, {depth = 2}))

   -- print(inspect(translate(x.v), {depth = 2}))
   -- print(inspect(translate(x.m), {depth = 2}))

   return R.connect{
      input = translate(x.v),
      toModule = translate(x.m),
   }
end

function translate.select(x)
   return R.selectStream{
      input = translate(x.v).inputs[1],
      index = x.n - 1,
   }
end

function translate.concat(x)
   local translated = {}
   local translated_t = {}
   for i,v in ipairs(x.vs) do
      translated_t[i] = translate(v.type)
      translated[i] = translate(v)

      -- print(inspect(translated_t[i], {depth = 2}))
      -- print(inspect(translated[i].type, {depth = 2}))
      translated_t[i] = translated[i].type.params.A
      -- if translated_t[i] ~= translated[i].type.params.A then

      -- end
   end

   return R.connect{
      input = R.concat(translated),
      toModule = RM.packTuple(translated_t),
   }
end

function translate.lambda(m)
   -- assuming the functions are memoized, then the translation of the input should still be the module's input in the Rigel version
   local x = translate(m.x)
   local f = translate(m.f)
   -- print(inspect(x, {depth = 2}))
   -- print(inspect(f, {depth = 2}))
   return R.defineModule{
      input = translate(m.x),
      output = translate(m.f),
   }
end

local function to_rigel(m)
   local in_size = { m.x.type.w, m.x.type.h }
   local out_size = {m.f.type.w, m.f.type.h }

   local res = translate(m)

   function synth(filename)
      local fname = arg[0]:match("([^/]+).lua")

      R.harness{
         fn = res,
         inFile = filename, inSize = in_size,
         outFile = fname, outSize = out_size,
         earlyOverride = 4800
      }
   end

   res.tag = "rigel"

   -- @todo: should this function maybe just call synth instead of returning it?
   return res, synth
end

if _VERBOSE then
   for k,v in pairs(translate) do
      translate[k] = function(m)
         log.trace('translate.' .. k .. '(...)')
         return v(m, util)
      end
   end
end


return to_rigel
