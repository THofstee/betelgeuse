local log = require 'log'
local inspect = require 'inspect'

local _VERBOSE = true

-- unique id generator
local id = 0
local function newid()
   id = id + 1
   return "id" .. id
end

-- map ir nodes to their ids
local ids = {}
local ids_mt = {
   __index = function(tbl, key)
      -- create a new id if one doesn't exist already
      tbl[key] = newid()
      return tbl[key]
   end
}
setmetatable(ids, ids_mt)

local function newvar(m, str)
   return string.format("local %s = %s", ids[m], str)
end

local s = {}

local dump = {}
local dump_mt = {
   __call = function(t, m)
      if rawget(ids, m) then return ids[m] end

      if _VERBOSE then log.trace("dump." .. m.kind) end
      if m.generator then
         assert(t[m.generator], "dispatch function " .. m.generator .. " is nil")
         return t[m.generator](m)
      else
         assert(t[m.kind], "dispatch function " .. m.kind .. " is nil")
         return t[m.kind](m)
      end
   end
}
setmetatable(dump, dump_mt)

--[[
   TYPES
--]]

function dump.uint(t)
   return string.format("R.uint(%s)", t.precision)
end

function dump.int(t)
   return string.format("R.int(%s)", t.precision)
end

function dump.array(t)
   return string.format("R.array2d(%s, %s, %s)",
                        dump(t.over), t.size[1], t.size[2])
end

function dump.tuple(t)
   local types = {}
   for i, typ in ipairs(t.list) do
      types[i] = dump(typ)
   end

   return string.format("R.tuple({ %s })", table.concat(types, ", "))
end

function dump.Handshake(t)
   return string.format("R.HS(%s)", dump(t.params.A))
end

function dump.named(t)
   assert(false)
end

--[[
   VALUES
--]]

function dump.input(i)
   s[#s+1] = newvar(i, string.format("R.input(%s)", dump(i.type)))
end

function dump.const(c)
   s[#s+1] = newvar(c, string.format("R.const(%s, %s)", dump(c.type), c.v))
end

function dump.concat(c)
   local types = {}
   for i,v in ipairs(c.inputs) do
      dump(v)
      types[i] = ids[v]
   end

   s[#s+1] = newvar(c, string.format("R.concat({ %s })",
                                     table.concat(types, ", ")))
end

function dump.select(a)
   dump(a.v)
   s[#s+1] = newvar(c, string.format("R.select(%s, %s)", ids[a.v], a.n))
end

function dump.apply(a)
   dump(a.fn)

   if #(a.inputs) == 1 then
      dump(a.inputs[1])
      s[#s+1] = newvar(a, string.format("R.connect{ input = %s, toModule = %s }",
                                        ids[a.inputs[1]], ids[a.fn]))
   elseif #(a.inputs) > 1 then
      print(inspect(a, {depth = 2}))
      assert(false)
   else
      s[#s+1] = newvar(a, string.format("R.connect{ toModule = %s }", ids[a.fn]))
   end

end

--[[
   MODULES
--]]

function dump.lift(m)
   if not m.generator then
      print(inspect(m, {depth = 2}))
      local str = m.name:match("([^_]*)_")
      assert(dump[str], "dispatch function " .. str .. " is nil")
      dump[str](m)
   else
      assert(dump[m.generator], "dispatch function " .. m.generator .. " is nil")
      dump[m.generator](m)
   end
end

dump["C.sum"] = function(m)
   local async = m.name:match("async_(.*)")
   local str = "R.modules.sum{ inType = %s, outType = %s, async = %s }"
   s[#s+1] = newvar(m, str:format(
                       dump(m.inputType.list[1]), dump(m.outputType), async))
end

dump["C.cast"] = function(m)
   s[#s+1] = newvar(m, string.format("C.cast(%s, %s)",
                                     dump(m.inputType), dump(m.outputType)))
end

dump["C.shiftAndCast"] = function(m)
   local shift = m.name:match("shift_(%d+)")
   local str = "R.modules.shiftAndCast{ inType = %s, outType = %s, shift = %s }"
   s[#s+1] = newvar(m, str:format(dump(m.inputType), dump(m.outputType), shift))
end

dump["C.slice"] = function(m)
   print(inspect(m, {depth = 2}))

   local x_lo = m.name:match("xl(%d+)_")
   local x_hi = m.name:match("xh(%d+)_")
   local y_lo = m.name:match("yl(%d+)_")
   local y_hi = m.name:match("yh(%d+)_")
   local idx = m.name:match("index(.*)")

   s[#s+1] = newvar(m, string.format("C.slice(%s, %s, %s, %s, %s, %s)",
                                     dump(m.inputType),
                                     x_lo, x_hi, y_lo, y_hi, idx))
end

dump["C.broadcast"] = function(m)
   local W = m.name:match("W(%d+)_")
   local H = m.name:match("H(%d+)_")
   s[#s+1] = newvar(m, string.format("C.broadcast(%s, %s, %s)",
                                     dump(m.inputType), W, H))
end

dump["C.downsampleSeq"] = function(m)
   local V = m.inputType.params.A.size[1] * m.inputType.params.A.size[2]
   local W = m.name:match("W(%d+)_")
   local H = m.name:match("H(%d+)_")
   local X = m.name:match("scaleX(%d+)_")
   local Y = m.name:match("scaleY(%d+)")

   local str =
      "R.modules.downsampleSeq{ type = %s, V = %s, size = { %s }, scale = { %s } }"
   s[#s+1] = newvar(m, str:format(
                       dump(m.inputType.params.A.over),
                       V,
                       table.concat({ W, H }, ", "),
                       table.concat({ X, Y }, ", ")))
end

dump["DownsampleXSeq"] = function(m)
   print(inspect(m, {depth = 2}))
   assert(false)
end

function dump.index(m)
   print(inspect(m, {depth = 2}))
   assert(false)
end

function dump.constSeq(m)
   local str = "R.modules.constSeq{ type = %s, P = %s, value = { %s } }"
   local typ = string.format("R.array2d(%s, %s, %s)", dump(m.A), m.w, m.h)
   s[#s+1] = newvar(m, str:format(typ, m.T, table.concat(m.value, ", ")))
end

function dump.map(m)
   dump(m.fn)
   s[#s+1] = newvar(m,
                    string.format("R.modules.map{ fn = %s, size = { %s, %s } }",
                                  ids[m.fn], m.W, m.H))
end

function dump.makeHandshake(m)
   dump(m.fn)
   s[#s+1] = newvar(m, string.format("R.HS(%s)", ids[m.fn]))
end

function dump.liftHandshake(m)
   dump(m.fn)
   s[#s+1] = newvar(m, string.format("R.HS(%s)", ids[m.fn]))
end

function dump.liftDecimate(m)
   dump(m.fn)
   s[#s+1] = newvar(m, ids[m.fn])
end

function dump.waitOnInput(m)
   dump(m.fn)
   s[#s+1] = newvar(m, ids[m.fn])
end

function dump.packTuple(m)
   local types = {}
   for i,t in ipairs(m.inputType.params.list) do
      types[i] = dump(t)
   end

   s[#s+1] = newvar(m, string.format("M.packTuple({ %s })",
                                     table.concat(types, ", ")))
end

function dump.RPassthrough(m)
   dump(m.fn)
   s[#s+1] = newvar(m, ids[m.fn])
end

function dump.changeRate(m)
   s[#s+1] = newvar(m, string.format("R.modules.changeRate{ type = %s, H = %s, inW = %s, outW = %s }", dump(m.type), m.H, m.inputRate, m.outputRate))
end

function dump.lambda(l)
   dump(l.input)
   dump(l.output)
   s[#s+1] = newvar(l, string.format("R.defineModule{ input = %s, output = %s }",
                                     ids[l.input], ids[l.output]))
end

local function entry(m)
   s[#s+1] = "local R = require 'rigelSimple'"
   s[#s+1] = "local M = require 'modules'"
   s[#s+1] = "local C = require 'examplescommon'"
   dump(m)
   s[#s+1] = string.format("id%s.tag = 'rigel'", id)
   s[#s+1] = string.format("return id%s", id)
   return table.concat(s, "\n")
end

return entry
