local Graphviz = require 'graphviz'
local inspect = require 'inspect'

local function str(s)
   return "\"" .. tostring(s) .. "\""
end

local function graph_view(l)
   local L = require 'betelgeuse.lang'
   
   local dot = Graphviz()

   local function typestr(t)
	  if t.kind == 'array2d' then
		 return typestr(t.t) .. '[' .. t.w .. ',' .. t.h .. ']'
	  elseif t.kind == 'uint' then
		 return 'uint' .. t.n
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

   -- generate graph from nodes
   local a = {}
   local a_mt = {
	  __call = function(a, node)
		 local node = L.unwrap(node)
		 assert(a[node.kind], "dispatch function " .. node.kind .. " is nil")
		 return a[node.kind](node)
	  end
   }
   setmetatable(a, a_mt)

   function a.apply(l)
	  dot:node(ids[l], l.m.kind)
	  a(l.v)
	  dot:edge(ids[l.v], ids[l])
	  return ids[l]
   end

   function a.concat(l)
	  dot:node(ids[l], l.kind)
	  for _,v in ipairs(l.vs) do
		 a(v)
		 dot:edge(ids[v], ids[l])
	  end
	  
	  return ids[l]
   end

   function a.input(l)
	  dot:node(ids[l], l.kind.. '\\n' .. typestr(l.type))
	  return ids[l]
   end

   function a.const(l)
	  dot:node(ids[l], l.kind)
	  return ids[l]
   end

   function a.lambda(l, create_input)
	  local create_input = create_input or true

	  -- create input unless specified not to (e.g. from apply)
	  if create_input then
		 local input = dot:node(ids[l.x], l.x.kind)
		 input.shape = 'Mdiamond'
	  end

	  -- save graph state
	  local old = dot

	  -- move into a cluster subgraph
	  dot = dot:subgraph('cluster_' .. ids[l])

	  -- generate lambda body
	  a(l.f)

	  -- restore graph state
	  dot = old

	  -- return the input to the apply
	  return ids[l.x]
   end
   
   a(l)

   dot:write('dbg/graph.dot')
   --    -- dot:compile('dbg/graph.dot', 'png')
   
   --    -- -- print(inspect(r, options))
   dot:render('dbg/graph.dot', 'png')
   -- assert(false)
   
end

-- local function graph_view(r)
--    local dot = Graphviz()


--    -- local options = {
--    -- 	  depth = 2,
--    -- 	  process = function(item, path)
--    -- 		 if(item == 'loc') then
--    -- 			return nil
--    -- 		 end
--    -- 		 return item
--    -- 	  end
--    -- }

--    -- local verbose = true
--    -- local a = {}
--    -- setmetatable(a, dispatch_mt)

--    -- function a.input(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, r.kind .. '(' .. tostring(r.type) .. ')')
--    -- 	  return ident
--    -- end

--    -- function a.apply(r)
--    -- 	  local ident = str(r)

--    -- 	  if verbose then	   
--    -- 		 dot:node(ident, "apply")
--    -- 		 dot:edge(a(r.fn), ident)
--    -- 		 dot:edge(a(r.inputs[1]), ident)
--    -- 	  else
--    -- 		 dot:edge(a(r.inputs[1]), a(r.fn))
--    -- 	  end

--    -- 	  return ident
--    -- end

--    -- function a.liftHandshake(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "liftHandshake")
--    -- 	  dot:edge(a(r.fn), ident)
--    -- 	  return ident
--    -- end

--    -- function a.changeRate(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "changeRate[" .. r.inputRate .. "->" .. r.outputRate .. "]")
--    -- 	  return ident
--    -- end

--    -- function a.waitOnInput(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "waitOnInput")
--    -- 	  dot:edge(a(r.fn), ident)
--    -- 	  return ident
--    -- end

--    -- function a.map(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "map")
--    -- 	  return ident
--    -- end

--    -- a["lift_slice_typeuint8[1,1]_xl0_xh0_yl0_yh0"] = function(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "lift_slice_typeuint8[1,1]_xl0_xh0_yl0_yh0")
--    -- 	  return ident
--    -- end

--    -- function a.concatArray2d(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "concatArray2d")
--    -- 	  return ident
--    -- end

--    -- function a.makeHandshake(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, "makeHandshake")
--    -- 	  dot:edge(a(r.fn), ident)
--    -- 	  return ident
--    -- end

--    -- function a.fn(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:edge(ident, "fn")
--    -- 	  return ident
--    -- end

--    -- function a.lambda(r)
--    -- 	  local ident = str(r)
--    -- 	  dot:node(ident, r.kind)
--    -- 	  dot:edge(a(r.input), ident)
--    -- 	  dot:edge(a(r.output), ident)
--    -- 	  return ident
--    -- end

--    -- a(r)
--    -- dot:write('dbg/graph.dot')
--    -- dot:compile('dbg/graph.dot', 'png')

--    -- -- print(inspect(r, options))
--    -- -- dot:render('dbg/graph.dot', 'png')
-- end

return graph_view
