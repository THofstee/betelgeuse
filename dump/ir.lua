local log = require 'log'
local inspect = require 'inspect'

local _VERBOSE = false

-- unique id generator
local id = 0
local function newid()
   id = id + 1
   return "id" .. id
end

-- map ir nodes to their ids
local ids_mt = {
   __index = function(tbl, key)
      -- create a new id if one doesn't exist already
      tbl[key] = newid()
      return tbl[key]
   end
}
local ids = setmetatable({}, ids_mt)

local function newvar(m, str)
   return string.format("local %s = %s", ids[m], str)
end

local s = {}

local dump = {}
local dump_mt = {
   __call = function(t, m)
      if rawget(ids, m) then return ids[m] end

      if _VERBOSE then log.trace("dump." .. m.kind) end
      assert(t[m.kind], "dispatch function " .. m.kind .. " is nil")
      return t[m.kind](m)
   end
}
setmetatable(dump, dump_mt)

--[[
   TYPES
--]]

function dump.bit(t)
   return string.format("I.bit(%s)", t.n)
end

function dump.array2d(t)
   return string.format("I.array2d(%s, %s, %s)", dump(t.t), t.w, t.h)
end

function dump.tuple(t)
   local types = {}
   for i, typ in ipairs(t.ts) do
      types[i] = dump(typ)
   end

   return string.format("I.tuple(%s)", table.concat(types, ", "))
end

--[[
   VALUES
--]]

function dump.input(i)
   s[#s+1] = newvar(i, string.format("I.input(%s)", dump(i.type)))
end

function dump.const(c)
   s[#s+1] = newvar(c, string.format("I.const(%s, %s)", dump(c.type), c.v))
end

function dump.concat(c)
   local values = {}
   for i,v in ipairs(c.vs) do
      dump(v)
      values[i] = ids[v]
   end

   s[#s+1] = newvar(c, string.format("I.concat(%s)", table.concat(values, ", ")))
end

function dump.select(a)
   dump(a.v)
   s[#s+1] = newvar(a, string.format("I.select(%s, %s)", ids[a.v], a.n))
end

function dump.apply(a)
   dump(a.m)
   dump(a.v)
   s[#s+1] = newvar(a, string.format("I.apply(%s, %s)", ids[a.m], ids[a.v]))
end

--[[
   MODULES
--]]

function dump.add(m)
   -- @todo: this shouldn't be a newvar probably
   s[#s+1] = newvar(m, string.format("I.add()"))
end

function dump.sub(m)
   s[#s+1] = newvar(m, string.format("I.sub()"))
end

function dump.mul(m)
   s[#s+1] = newvar(m,string.format("I.mul()"))
end

function dump.div(m)
   s[#s+1] = newvar(m, string.format("I.div()"))
end

function dump.shift(m)
   s[#s+1] = newvar(m, string.format("I.shift(%s)", m.n))
end

function dump.trunc(m)
   s[#s+1] = newvar(m, string.format("I.trunc(%s)", m.n))
end

function dump.zip(m)
   s[#s+1] = newvar(m, string.format("I.zip(%s)", dump(m.m)))
end

function dump.partition(m)
   s[#s+1] = newvar(m, string.format("I.partition({ %s })",
                                     table.concat(m.counts, ", ")))
end

function dump.flatten(m)
   s[#s+1] = newvar(m, string.format("I.flatten({ %s })",
                                     table.concat(m.size, ", ")))
end

function dump.map_x(m)
   dump(m.m)
   s[#s+1] = newvar(m, string.format("I.map_x(%s, { %s })",
                                     ids[m.m], table.concat(m.size, ", ")))
end

function dump.map_t(m)
   dump(m.m)
   s[#s+1] = newvar(m, string.format("I.map_t(%s, { %s })",
                                     ids[m.m], table.concat(m.size, ", ")))
end

function dump.reduce_x(m)
   dump(m.m)
   s[#s+1] = newvar(m, string.format("I.reduce_x(%s, { %s })",
                                     ids[m.m], table.concat(m.size, ", ")))
end

function dump.reduce_t(m)
   dump(m.m)
   s[#s+1] = newvar(m, string.format("I.reduce_t(%s, { %s })",
                                     ids[m.m], table.concat(m.size, ", ")))
end

function dump.stencil_x(m)
   s[#s+1] = newvar(m, string.format("I.stencil_x(%s, %s, %s, %s)",
                                     m.offset_x, m.offset_y,
                                     m.extent_x, m.extent_y))
end

function dump.pad_t(m)
   s[#s+1] = newvar(m, string.format("I.pad_t(%s, %s, %s, %s)",
                                     m.left, m.right, m.top, m.bottom))
end

function dump.crop_t(m)
   s[#s+1] = newvar(m, string.format("I.crop_t(%s, %s, %s, %s)",
                                     m.left, m.right, m.top, m.bottom))
end

function dump.upsample_x(m)
   s[#s+1] = newvar(m, string.format("I.upsample_x(%s, %s)", m.x, m.y))
end

function dump.upsample_t(m)
   s[#s+1] = newvar(m, string.format("I.upsample_t(%s, %s, %s)",
                                     m.x, m.y, m.cycles))
end

function dump.downsample_x(m)
   s[#s+1] = newvar(m, string.format("I.downsample_x(%s, %s)", m.x, m.y))
end

function dump.downsample_t(m)
   s[#s+1] = newvar(m, string.format("I.downsample_t(%s, %s, %s)",
                                     m.x, m.y, m.cycles))
end

function dump.repeat_t(m)
   assert(false)
end

function dump.repeat_x(m)
   assert(false)
end

function dump.buffer(m)
   s[#s+1] = newvar(m, string.format("I.buffer(%s)", m.size))
end

function dump.lambda(l)
   local x = dump(l.x)
   local f = dump(l.f)
   s[#s+1] = newvar(l, string.format("I.lambda(%s, %s)", ids[l.f], ids[l.x]))
end

local function entry(m)
   id = 0
   ids = setmetatable({}, ids_mt)
   s = {}
   s[#s+1] = "local I = require 'betelgeuse.ir'"
   dump(m)
   s[#s+1] = string.format("return %s", "id" .. id)
   return table.concat(s, "\n")
end

return entry
