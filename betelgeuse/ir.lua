--- An intermediate representation for scheduling
-- @module ir
require 'betelgeuse.util'
local asdl = require 'asdl'
local List = asdl.List
local memoize = require 'memoize'

local IR = {}

local C = asdl.NewContext()
C:Define [[
Type = bit(number n) # @todo: should this be bit, uint/int, fixed, etc?
     | tuple(Type* ts)
     | array2d(Type t, number w, number h)

Value = input(Type t)
      | const(Type t, any v) # @todo: this is tricky, maybe it should be fixed point types like the high level language?
      | concat(Value* vs)
      | select(Value v, number n)
      | apply(Module m, Value v)
      attributes(Type type)

Module = add
       | sub
       | mul
       | div
       | shift(number n) # @todo: this is an expanding shift?
       | trunc(number n)
       | zip
# @todo: should all these modules that take in table size just take in two numbers x and y as parameters instead?
       | partition(table counts)
       | flatten(table size)
       | map_x(Module m, table size)
       | map_t(Module m, table size)
       | reduce_x(Module m, table size)
       | reduce_t(Module m, table size)
       | stencil_x(number offset_x, number offset_y, number extent_x, number extent_y)
       | pad_t(number left, number right, number top, number bottom)
       | crop_t(number left, number right, number top, number bottom)
       | upsample_x(number x, number y)
       | upsample_t(number x, number y, number cycles)
       | downsample_x(number x, number y)
       | downsample_t(number x, number y, number cycles)
       | repeat_x(number w, number h)
       | repeat_t(number w, number h)
       | lambda(Value f, input x)
       attributes(function type_func)
]]

--[[
   Types
--]]
function IR.bit(n)
   return C.bit(n)
end
IR.bit = memoize(IR.bit)

function IR.tuple(...)
   if #{...} == 1 then
      return C.tuple(List(...))
   else
      return C.tuple(List{...})
   end
end
IR.tuple = memoize(IR.tuple)

function IR.array2d(t, w, h)
   return C.array2d(t, w, h)
end
IR.array2d = memoize(IR.array2d)

--[[
   Values
--]]

function IR.input(t)
   return C.input(t, t)
end

function IR.const(t, v)
   return C.const(t, v, t)
end

function IR.concat(...)
   local ts = {}
   for i,v in ipairs({...}) do
      ts[i] = v.type
   end

   return C.concat(List{...}, IR.tuple(ts))
end

function IR.select(v, n)
   return C.select(v, n, v.type.ts[n])
end

function IR.apply(m, v)
   m.type_in = v.type
   m.type_out = m.type_func(v.type)
   return C.apply(m, v, m.type_out)
end

--[[
   Type functions
--]]

local function binop_type_func(t)
   assert(t.kind == 'tuple')
   assert(t.ts[1].kind == 'bit')
   return t.ts[1]
end

--[[
   Modules
--]]

function IR.add()
   return C.add(binop_type_func)
end

function IR.sub()
   return C.sub(binop_type_func)
end

function IR.mul()
   return C.mul(binop_type_func)
end

function IR.div()
   return C.div(binop_type_func)
end

function IR.shift(n)
   local function type_func(t)
      assert(t.kind == 'bit')
      return t
   end

   return C.shift(n, type_func)
end

function IR.trunc(n)
   local function type_func(t)
      return IR.bit(n)
   end

   return C.trunc(n, type_func)
end

function IR.zip()
   local function type_func(t)
      local w = t.ts[1].w
      local h = t.ts[1].h
      local types = {}
      for i,t  in ipairs(t.ts) do
         types[i] = t.t
      end
      return IR.array2d(L.tuple(types), w, h)
   end

   return C.zip(type_func)
end

local size_mt = {
   __eq = function(self, other)
      if #self ~= #other then return false end

      for i,v in ipairs(self) do
         if v ~= other[i] then return false end
      end
   end
}

function IR.partition(n)
   -- @todo: type function needs to be checked
   local function type_func(t)
      return IR.array2d(IR.array2d(t.t, n[1], n[2]), t.w/n[1], t.h/n[2])
   end

   return C.partition(setmetatable(n, size_mt), type_func)
end

function IR.flatten(n)
   -- @todo: type function needs to be revised. T[m][n] -> flatten k => ???
   local function type_func(t)
      return IR.array2d(t.t.t, t.w*t.t.w, t.h*t.t.h)
   end

   return C.flatten(setmetatable(n, size_mt), type_func)
end

function IR.map_x(f, n)
   local function type_func(t)
      -- @todo: should this be t.w and t.h or should it just be n?
      -- @todo: does map_x go from A[w,h] -> B[w,h] in chunks of n, or just from A[n] -> B[n]?
      return IR.array2d(f.type_func(t.t), t.w, t.h)
   end

   local res = C.map_x(f, n, type_func)

   -- propagate applied types through the modules
   local mt = getmetatable(res)
   function mt.__newindex(self, key, val)
      rawset(self, key, val)
      if key == 'type_in' then
         self.m.type_in = val.t
      elseif key == 'type_out' then
         self.m.type_out = val.t
      end
   end

   return res
end

function IR.map_t(f, n)
   local function type_func(t)
      -- @todo: should this be t.w and t.h or should it just be n?
      -- @todo: does map_x go from A[w,h] -> B[w,h] in chunks of n, or just from A[n] -> B[n]?
      return IR.array2d(f.type_func(t.t), t.w, t.h)
   end

   local res = C.map_t(f, n, type_func)

   -- propagate applied types through the modules
   local mt = getmetatable(res)
   function mt.__newindex(self, key, val)
      rawset(self, key, val)
      if key == 'type_in' then
         self.m.type_in = val.t
      elseif key == 'type_out' then
         self.m.type_out = val.t
      end
   end

   return res
end

function IR.reduce_x(f, n)
   return C.reduce_x(f, n)
end

function IR.reduce_t(f, n)
   return C.reduce_t(f, n)
end

function IR.stencil_x(x0, y0, x1, y1)
   return C.stencil_x(x0, y0, x1, y1)
end

function IR.pad_t(l, r, t, b)
   return C.pad_t(l, r, t, b)
end

function IR.crop_t(l, r, t, b)
   return C.crop_t(l, r, t, b)
end

function IR.upsample_x(x, y)
   local function type_func(t)
      return IR.array2d(t.t, t.w*x, t.h*y)
   end

   return C.upsample_x(x, y, type_func)
end

function IR.upsample_t(x, y, cyc)
   return C.upsample_t(x, y, cyc)
end

function IR.downsample_x(x, y)
   local function type_func(t)
      return IR.array2d(t.t, t.w/x, t.h/y)
   end

   return C.downsample_x(x, y, type_func)
end

function IR.downsample_t(x, y, cyc)
   return C.downsample_t(x, y, cyc)
end

function IR.repeat_x(w, h)
   return C.repeat_x(w, h)
end

function IR.repeat_t(w, h)
   return C.repeat_t(w, h)
end

function IR.lambda(f, x)
   local function type_func(t)
      assert(t == x.type, string.format('Type of input (%s) does not match expected type (%s)', t, x.type))
      return f.type
   end

   return C.lambda(f, x, type_func)
end

return IR
