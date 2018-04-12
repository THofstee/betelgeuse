local L = require 'betelgeuse.lang'
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
      assert(t[m.kind], "dispatch function " .. m.kind .. " is nil")
      return t[m.kind](m)
   end
}
setmetatable(dump, dump_mt)

function dump.wrapped(w)
   return dump(L.unwrap(w))
end

function dump.array2d(t)
   return string.format("L.array2d(%s, %s, %s)", dump(t.t), t.w, t.h)
end

function dump.fixed(t)
   return string.format("L.fixed(%s, %s)", t.i, t.f)
end

function dump.tuple(t)
   local types = {}
   for i, typ in ipairs(t.ts) do
      types[i] = dump(typ)
   end

   return string.format("L.tuple(%s)", table.concat(types, ", "))
end

function dump.input(i)
   s[#s+1] = newvar(i, string.format("L.input(%s)", dump(i.type)))
end

function dump.const(c)
   s[#s+1] = newvar(c, string.format("L.const(%s, %s)", dump(c.type), c.v))
end

function dump.broadcast(m)
   return C.broadcast(
      dump(m.type.t),
      m.w,
      m.h
   )
end

function dump.concat(c)
   local values = {}
   for i,v in ipairs(c.vs) do
      dump(v)
      values[i] = ids[v]
   end

   s[#s+1] = newvar(c, string.format("L.concat(%s)", table.concat(values, ", ")))
end

function dump.select(a)
   return R.index{
      input = dump(a.v),
      key = a.n-1
   }
end

function dump.add(m)
   -- @todo: this shouldn't be a newvar probably
   s[#s+1] = newvar(m, string.format("L.add()"))
end

function dump.sub(m)
   s[#s+1] = string.format("L.sub()")
end

function dump.mul(m)
   s[#s+1] = string.format("L.mul()")
end

function dump.div(m)
   s[#s+1] = string.format("L.div()")
end

function dump.shift(m)
   s[#s+1] = string.format("L.shift(%s)", m.n)
end

function dump.trunc(m)
   s[#s+1] = string.format("L.trunc(%s, %s)", m.i, m.f)
end

function dump.reduce(m)
   s[#s+1] = string.format("L.reduce(%s)", dump(m.m))
end

function dump.pad(m)
   s[#s+1] = string.format("L.pad(%s, %s, %s, %s)",
                        m.left, m.right, m.top, m.bottom
   )
end

function dump.crop(m)
   s[#s+1] = string.format("L.crop(%s, %s, %s, %s)",
                        m.left, m.right, m.top, m.bottom
   )
end

function dump.upsample(m)
   s[#s+1] = newvar(m, string.format("L.upsample(%s, %s)", m.x, m.y))
end

function dump.downsample(m)
   s[#s+1] = newvar(m, string.format("L.downsample(%s, %s)", m.x, m.y))
end

function dump.stencil(m)
   s[#s+1] = string.format("L.stencil(%s, %s, %s, %s)",
                        m.offset_x, m.offset_y,
                        m.extent_x, m.extent_y
   )
end

function dump.buffer(m)
   return R.buffer{
      type = dump(m.in_type),
      depth = m.size,
   }
end

function dump.lambda(l)
   local x = dump(l.x)
   local f = dump(l.f)
   s[#s+1] = newvar(l, string.format("L.lambda(%s, %s)", ids[l.f], ids[l.x]))
end

function dump.apply(a)
   dump(a.m)
   dump(a.v)
   s[#s+1] = newvar(a, string.format("L.apply(%s, %s)", ids[a.m], ids[a.v]))
end

function dump.map(m)
   dump(m.m)
   s[#s+1] = newvar(m, string.format("L.map(%s)", ids[m.m]))
end

function dump.zip(m)
   s[#s+1] = string.format("L.zip(%s)", dump(m.m))
end

local function entry(m)
   s[#s+1] = "local L = require 'betelgeuse.lang'"
   dump(m)
   s[#s+1] = string.format("return %s", "id" .. id)
   return table.concat(s, "\n")
end

return entry
