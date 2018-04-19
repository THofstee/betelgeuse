local R = require 'rigelSimple'
local rtypes = require 'types'
local C = require 'examplescommon'
local RM = require 'modules'

local inspect = require 'inspect'
local memoize = require 'memoize'
local log = require 'log'

local _VERBOSE = false

-- local function flatten(t)
--    local res = {}
--    for _,v in ipairs(t) do
--       print(v)
--    end
-- end

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

local function cast(input, t)
   if input.type.params.A == t then return input end

   return R.connect{
      input = input,
      toModule = R.HS(
         C.cast(
            input.type.params.A,
            t
         )
      )
   }
end

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

   if w == out_size[1] and h == out_size[2] then
      return R.defineModule{
         input = input,
         output = input,
      }
   end

   local in_cast = cast(input, R.array2d(arr_t, w*h, 1))

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

   local output = cast(rate, R.array2d(arr_t, w_out, h_out))

   return R.defineModule{
      input = input,
      output = output
   }
end

local translate = {}
local translate_mt = {
   __call = memoize(function(translate, m, hs)
         assert(m)
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

      local inter = R.connect{
         input = nil,
         toModule = R.HS(m),
      }

      return cast(inter, translate(x.type, false))
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
      -- local m = R.HS(
      --    R.modules.upsampleSeq{
      --       type = translate(m.type_in.t, false),
      --       V = 2, -- @todo: is this correct?
      --       size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
      --       scale = { m.x, m.y },
      --    }
      -- )

      local input = R.input(translate(m.type_in, hs))

      -- @todo: hack, this shouldn't be a broadcast if it can be avoided
      local inter = R.connect{
         input = input,
         toModule = R.HS(
            C.broadcast(
               translate(m.type_in, false),
               m.type_out.w / m.type_in.w,
               m.type_out.h / m.type_in.h
            )
         )
      }

      local cast = cast(
         inter,
         R.array2d(translate(m.type_in.t, false), m.type_out.w, m.type_out.h)
      )

      -- @todo: bug here in this cast
      -- print(inter.type.params.A)
      -- print(R.array2d(translate(m.type_in.t, false), m.type_out.w, m.type_out.h))

      return R.defineModule{
         input = input,
         output = cast,
      }

      -- return R.HS(
      --    R.modules.upsampleSeq{
      --       type = translate(m.type_in.t, false),
      --       V = 1, -- @todo: is this correct?
      --       size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
      --       scale = { m.x, m.y },
      --    }
      -- )
   else
      return R.modules.upsample{
         type = translate(m.type_in.t, false),
         size = { m.type_in.w, m.type_in.h },
         scale = { m.x, m.y },
      }
   end
end

function translate.upsample_t(m, hs)
   if hs then
      local input = R.input(translate(m.type_in, hs))

      print("AA", inspect(m, {depth = 2}))

      local new_m = R.modules.upsampleSeq{
         type = translate(m.type_in.t, false),
         V = m.type_in.w*m.type_in.h, -- @todo: is this correct?
         size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
         scale = { m.x, m.y },
      }

      print("AB", inspect(new_m, {depth = 2}))

      local inter = R.connect{
         input = input,
         toModule = R.HS(new_m)
      }

      print("AC", inspect(inter, {depth = 2}))
      -- local rate = R.connect{
      --    input = inter,
      --    toModule = change_rate(
      --       inter.type.params.A,
      --       { m.type_out.w, m.type_out.h }
      --    )
      -- }

      return R.defineModule{
         input = input,
         output = inter
      }
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
      local input = R.input(translate(m.type_in, hs))

      local new_m
      -- For some reason, downsampleSeq is super slow when y == 1.
      if m.y == 1 then
         new_m = RM.downsampleXSeq(
            translate(m.type_in.t, false),
            m.type_in.w, -- @todo: this is wrong, see below
            m.type_in.h, -- @todo: this is wrong, see below
            m.type_in.w*m.type_in.h, -- @todo: is this correct?
            m.x
         )
      else
         new_m = R.modules.downsampleSeq{
               type = translate(m.type_in.t, false),
               V = m.type_in.w*m.type_in.h, -- @todo: is this correct?
               size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
               scale = { m.x, m.y },
            }
      end

      local inter = R.connect{
         input = input,
         toModule = R.HS(new_m)
      }

      local rate = R.connect{
         input = inter,
         toModule = change_rate(
            inter.type.params.A,
            { m.type_out.w, m.type_out.h }
         )
      }

      return R.defineModule{
         input = input,
         output = rate,
      }
   else
      return R.modules.downsample{
         type = translate(m.type_in.t, hs),
         size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
         scale = { m.x, m.y },
      }
   end
end

function translate.downsample_t(m, hs)
   if hs then
      -- print(inspect(m, {depth = 2}))
      local input = R.input(R.HS(R.array2d(translate(m.type_in.t, false), 1, 1)))

      local new_m
      -- For some reason, downsampleSeq is super slow when y == 1.
      if m.y == 1 then
         new_m = RM.downsampleXSeq(
            translate(m.type_in.t, false),
            m.type_in.w, -- @todo: this is wrong, see below
            -- 1,
            m.type_in.h, -- @todo: this is wrong, see below
            -- 1,
            1, --m.type_in.w*m.type_in.h, -- @todo: is this correct?
            m.x
         )
      else
         new_m = R.modules.downsampleSeq{
               type = translate(m.type_in.t, false),
               V = m.type_in.w*m.type_in.h, -- @todo: is this correct?
               size = { m.type_in.w, m.type_in.h }, -- @todo: this is wrong, it needs to pass in the width and height of the full image through the IR translations
               scale = { m.x, m.y },
            }
      end

      local inter = R.connect{
         input = input,
         toModule = R.HS(new_m)
      }

      local rate = R.connect{
         input = inter,
         toModule = change_rate(
            inter.type.params.A,
            { m.type_out.w, m.type_out.h }
         )
      }

      return R.defineModule{
         input = input,
         output = rate,
      }
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
   -- local out_size = { m.type_out.w, m.type_out.h }
   -- local new_m = translate(m.m, hs)

   -- local input = R.input(translate(m.type_in, hs))

   -- local flatten = R.connect{
   --    input = input,
   --    toModule = change_rate(translate(m.type_in, false), { 1, 1 })
   -- }

   -- local inter = R.connect{
   --    input = input,
   --    toModule = new_m,
   -- }

   -- local output = R.connect{
   --    input = inter,
   --    toModule = change_rate(new_m.outputType.params.A, out_size),
   -- }

   -- return R.defineModule{
   --    input = input,
   --    output = inter,
   -- }
end

function translate.partition(m, hs)
   -- @todo: this is weird
   return change_rate(translate(m.type_in, false), m.counts)
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
   print(inspect(x.v, {depth = 2}))
   print(inspect(x.m, {depth = 2}))
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
   for i,v in ipairs(x.vs) do
      translated[i] = translate(v, hs)
   end

   if hs then
      return R.fanIn(translated)
   else
      -- print(inspect(R.concat(translated), {depth = 2}))
      return R.concat(translated)
   end
end

function translate.lambda(m, hs)
   -- assuming the functions are memoized, then the translation of the input should still be the module's input in the Rigel version
   local x = translate(m.x, hs)
   local f = translate(m.f, hs)
   -- print("L1", inspect(m.x, {depth = 2}))
   -- print("L2", inspect(m.f, {depth = 2}))
   -- print("LA", inspect(x, {depth = 2}))
   -- print("LB", inspect(f, {depth = 2}))
   return R.defineModule{
      input = translate(m.x, hs),
      output = translate(m.f, hs),
   }
end

local function inline_hs(m, input)
   local function f(cur, inputs)
      print(cur.kind)
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
   end

   return m.output:visitEach(f)
end

local function make_mem_happy(m)
   if m.inputType.params.A.kind == 'array' then
      local input = R.input(R.HS(R.array2d(rtypes.uint(8), m.inputType.params.A.size[1], m.inputType.params.A.size[2])))

      local cast = R.connect{
         input = input,
         toModule = R.HS(
            R.modules.map{
               fn = C.cast(
                  rtypes.uint(8),
                  m.inputType.params.A.over
               ),
               size = m.inputType.params.A.size
            }
         )
      }

      local temp = R.connect{
         input = cast,
         toModule = m
      }

      if m.outputType.params.A.over then
         local output = R.connect{
            input = temp,
            toModule = R.HS(
               R.modules.map{
                  fn = C.cast(
                     m.outputType.params.A.over,
                     rtypes.uint(8)
                  ),
                  size = m.outputType.params.A.size
               }
            )
         }

         return R.defineModule{
            input = input,
            output = output
         }
      else
         local output = R.connect{
            input = temp,
            toModule = R.HS(
               R.modules.map{
                  fn = C.cast(
                     m.outputType.params.A,
                     rtypes.uint(8)
                  ),
                  size = { 1, 1 }
               }
            )
         }

         return R.defineModule{
            input = input,
            output = output
         }
      end
   else
      local input = R.input(R.HS(rtypes.uint(8)))

      local cast = R.connect{
         input = input,
         toModule = R.HS(
            C.cast(
               rtypes.uint(8),
               m.inputType.params.A
            )
         )
      }

      local temp = R.connect{
         input = cast,
         toModule = m
      }

      local output = R.connect{
         input = temp,
         toModule = R.HS(
            R.modules.map{
               fn = C.cast(
                  -- m.outputType.params.A.over,
                  m.outputType.params.A,
                  rtypes.uint(8)
               ),
               -- size = m.outputType.params.A.size
               size = { 1, 1 }
            }
         )
      }

      return R.defineModule{
         input = input,
         output = output
      }
   end
end

local function to_rigel(m)
   local in_size = { m.x.type.w, m.x.type.h }
   local out_size = {m.f.type.w, m.f.type.h }
   local m = m.f.v.m.m or m.f.v.v.m.m

   local res = translate(m, true)
   res = make_mem_happy(res)

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
