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
   __call = memoize(function(translate, m, hs)
         local dispatch = m.kind
         assert(hs ~= nil, "hs was nil")
         assert(translate[dispatch], "dispatch function " .. dispatch .. " is nil")
         return translate[dispatch](m, hs)
   end)
}
setmetatable(translate, translate_mt)

function translate.bit(t, hs)
   if hs then
      return R.HS(rtypes.int(math.ceil(t.n/8)*8))
   else
      return rtypes.int(math.ceil(t.n/8)*8)
   end
end

function translate.array2d(t, hs)
   if hs then
      return R.HS(R.array2d(translate(t.t, false), t.w, t.h))
   else
      return R.array2d(translate(t.t, false), t.w, t.h)
   end
end

function translate.tuple(t, hs)
   local translated = {}
   for i, typ in ipairs(t.ts) do
      translated[i] = translate(typ, hs)
   end

   return R.tuple(translated)
end

function translate.input(x, hs)
   return R.input(translate(x.type, hs))
end

function translate.const(x, hs)
   if hs then
      -- print(inspect(x, {depth = 2}))
      -- return R.modules.constSeq{
      --    type = R.array2d(translate(x.type), 1, 1),
      --    P = 1,
      --    value = { flatten(x.v) },
      -- }
      local m = R.modules.constSeq{
         type = R.array2d(translate(x.type, false), 1, 1),
         P = 1,
         value = { x.v },
      }

      return R.connect{
         input = nil,
         toModule = R.HS(m),
      }
   else
      return R.constant{
         type = translate(x.type, false),
         value = x.v,
      }
   end
end

function translate.add(m, hs)
   local m = R.modules.sum{
      inType = translate(m.type_in.ts[1], false),
      outType = translate(m.type_out, false),
      async = true
   }

   if hs then return R.HS(m) else return m end
end

function translate.trunc(m, hs)
   -- @todo: is there another way of doing this?
   local m = R.modules.shiftAndCast{
      inType = translate(m.type_in, false),
      outType = translate(m.type_out, false),
      shift = 0
   }

   if hs then return R.HS(m) else return m end
end

function translate.shift(m, hs)
   local m = R.modules.shiftAndCast{
      inType = translate(m.type_in, false),
      outType = translate(m.type_out, false),
      shift = m.n,
   }

   if hs then return R.HS(m) else return m end
end

function translate.upsample_x(m, hs)
   if hs then
      -- print(inspect(m, {depth = 2}))
      return R.HS(
         R.modules.upsampleSeq{
            type = translate(m.type_in.t, false),
            V = 1, -- @todo: is this correct?
            size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
            scale = { m.x, m.y },
         }
      )
   else
      return R.modules.upsample{
         type = translate(m.type_in.t, false),
         size = { m.type_in.w, m.type_in.h },
         scale = { m.x, m.y },
      }
   end
end

function translate.downsample_x(m, hs)
   if hs then
      -- print(inspect(m, {depth = 2}))
      return R.HS(
         R.modules.downsampleSeq{
            type = translate(m.type_in.t, hs),
            V = 1, -- @todo: is this correct?
            size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
            scale = { m.x, m.y },
         }
      )
   else
      return R.modules.downsample{
         type = translate(m.type_in.t, hs),
         size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
         scale = { m.x, m.y },
      }
   end
end

function translate.map_x(m, hs)
   -- @todo: the translated module is handshaked, but we only want to handshake around the map instead of the internal modules too...
   -- print(inspect(translate(m.m), {depth = 2}))
   -- print(inspect(m.size))
   local m = R.modules.map{
      fn = translate(m.m, false),
      size = m.size,
   }
   -- local m = translate(m.m, false)
   if hs then return R.HS(m) else return m end
end

function translate.map_t(m, hs)
   return translate(m.m, hs)
end

function translate.partition(m, hs)
   -- @todo: this is weird
   return change_rate(translate(m.type_in, false), { 1, 1 })
end

function translate.flatten(m, hs)
   -- @todo: this is weird with the input type...
   return change_rate(translate(m.type_in.t, false), { m.type_out.w, m.type_out.h })
end

function translate.apply(x, hs)
   local v = translate(x.v, hs)
   local m = translate(x.m, hs)
   print('================')
   print('================')
   print('================')
   print('================')
   print(hs)
   print(inspect(v, {depth = 2}))
   print(inspect(m, {depth = 2}))

   return R.connect{
      input = translate(x.v, hs),
      toModule = translate(x.m, hs),
   }
end

function translate.select(x, hs)
   return R.selectStream{
      input = translate(x.v, hs).inputs[1],
      index = x.n - 1,
   }
end

function translate.concat(x, hs)
   local translated = {}
   local translated_t = {}
   for i,v in ipairs(x.vs) do
      translated_t[i] = translate(v.type, hs)
      translated[i] = translate(v, hs)

      -- print(inspect(translated_t[i], {depth = 2}))
      -- print(inspect(translated[i].type, {depth = 2}))
      if hs then
         translated_t[i] = translated[i].type.params.A
      else
         translated_t[i] = translated[i].type
      end
      -- if translated_t[i] ~= translated[i].type.params.A then

      -- end
   end

   if hs then
      return R.connect{
         input = R.concat(translated),
         toModule = RM.packTuple(translated_t),
      }
   else
      print(inspect(R.concat(translated), {depth = 2}))
      return R.concat(translated)
   end
end

function translate.lambda(m, hs)
   -- assuming the functions are memoized, then the translation of the input should still be the module's input in the Rigel version
   local x = translate(m.x, hs)
   local f = translate(m.f, hs)
   -- print(inspect(x, {depth = 2}))
   -- print(inspect(f, {depth = 2}))
   return R.defineModule{
      input = translate(m.x, hs),
      output = translate(m.f, hs),
   }
end

local function to_rigel(m)
   local in_size = { m.x.type.w, m.x.type.h }
   local out_size = {m.f.type.w, m.f.type.h }

   local res = translate(m, true)

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
      translate[k] = function(m, hs)
         log.trace('translate.' .. k .. '(...)')
         return v(m, hs)
      end
   end
end


return to_rigel
