local Graphviz = require 'graphviz'
local memoize = require 'memoize'

local function str(s)
   return "\"" .. tostring(s) .. "\""
end

local function graph_view(l)
   local dot = Graphviz()

   local function typestr(t)
      if t.kind == 'array2d' then
         return typestr(t.t) .. '[' .. t.w .. ',' .. t.h .. ']'
      elseif t.kind == 'fixed' then
         return 'fixed' .. t.i .. '.' .. t.f
      elseif t.kind == 'tuple' then
         local res = '{'
         for i,v in ipairs(t.ts) do
            res = res .. typestr(v) .. ','
         end
         res = string.sub(res, 1, -2) .. '}'
         return res
      else
         return tostring(t)
      end
   end

   -- unique id generator
   local id = 0
   local function newid()
      id = id + 1
      return 'id' .. id
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

   local info = {}
   local info_mt = {
      __call = function(info, node)
         if not info[node.kind] then
            return node.kind
         end
         return info[node.kind](node)
      end
   }
   setmetatable(info, info_mt)

   local a = {}
   local a_mt = {
      __call = memoize(function(a, node)
         assert(a[node.kind], "dispatch function a." .. node.kind .. " is nil")
         return a[node.kind](node)
      end)
   }
   setmetatable(a, a_mt)

   function info.add(m)
      return '+'
   end

   function info.sub(m)
      return '-'
   end

   function info.mul(m)
      return '*'
   end

   function info.crop(m)
      return 'crop' .. '\\n' .. '{' .. m.left .. ',' .. m.right .. ',' .. m.bottom .. ',' .. m.top .. '}'
   end

   function info.reduce(m)
      return 'reduce' .. '(' .. info(m.m) .. ')'
   end

   function info.map_t(m)
      return 'map_t' .. '(' .. info(m.m) .. ')'
   end

   function info.map_x(m)
      return 'map_x' .. '(' .. info(m.m) .. ')'
   end

   function info.zip(m)
      return 'zip'
   end

   function info.pad(m)
      return 'pad' .. '\\n' .. '{' .. m.left .. ',' .. m.right .. ',' .. m.bottom .. ',' .. m.top .. '}'
   end

   function info.broadcast(m)
      return 'broadcast' .. '\\n' .. '{' .. m.w .. ',' .. m.h .. '}'
   end

   function info.stencil(m)
      return 'stencil' .. '\\n' .. '{' .. m.offset_x .. ',' .. m.offset_y .. ',' .. m.extent_x .. ',' .. m.extent_y .. '}'
   end

   function info.lambda(m)
      a(m)
      return 'lambda'
   end

   -- generate graph from nodes
   function a.apply(l)
      if l.m.kind == 'lambda' then
         local i,o = a(l.m)
         dot:edge(a(l.v), i, str(typestr(l.v.type)))
         return o
      else
         dot:node(ids[l], info(l.m))
         dot:edge(a(l.v), ids[l], str(typestr(l.v.type)))
         return ids[l]
      end
   end

   function a.concat(l)
      dot:node(ids[l], l.kind)
      for i,v in ipairs(l.vs) do
         dot:edge(a(v), ids[l], str(tostring(i) .. ': ' .. typestr(v.type)))
      end

      return ids[l]
   end

   function a.select(l)
      dot:node(ids[l], l.kind .. '\\n' .. l.n)
      dot:edge(a(l.v), ids[l], str(typestr(l.v.type)))
      return ids[l]
   end

   function a.input(l)
      dot:node(ids[l], l.kind.. '\\n' .. typestr(l.type))
      return ids[l]
   end

   function a.const(l)
      dot:node(ids[l], l.kind .. '\\n' .. typestr(l.type))
      return ids[l]
   end

   function a.lambda(l)
      local input = dot:node(ids[l.x], l.x.kind)
      input.shape = 'Mdiamond'

      -- save graph state
      local old = dot

      -- move into a cluster subgraph
      dot = dot:subgraph('cluster_' .. ids[l])

      -- generate lambda body
      local out = a(l.f)

      -- restore graph state
      dot = old

      -- return the input to the apply
      return ids[l.x], out
   end

   a(l)

   dot:write('dbg/graph.dot')
   if (require'graphview').render then
      dot:render('dbg/graph.dot')
   end
end

return graph_view
