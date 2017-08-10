local Graphviz = require 'graphviz'
local inspect = require 'inspect'

local function str(s)
   return "\"" .. tostring(s) .. "\""
end

local function b_graph_view(l)
   local L = require 'betelgeuse.lang'
   
   local dot = Graphviz()

   local function typestr(t)
	  if t.kind == 'array2d' then
		 return typestr(t.t) .. '[' .. t.w .. ',' .. t.h .. ']'
	  elseif t.kind == 'uint' then
		 return 'uint' .. t.n
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
		 local node = L.unwrap(node)
		 assert(info[node.kind], "dispatch function info." .. node.kind .. " is nil")
		 return info[node.kind](node)
	  end
   }
   setmetatable(info, info_mt)

   function info.add(m)
	  return '+'
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

   function info.map(m)
	  return 'map' .. '(' .. info(m.m) .. ')'
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

   -- generate graph from nodes
   local a = {}
   local a_mt = {
	  __call = function(a, node)
		 local node = L.unwrap(node)
		 assert(a[node.kind], "dispatch function a." .. node.kind .. " is nil")
		 return a[node.kind](node)
	  end
   }
   setmetatable(a, a_mt)

   function a.apply(l)
	  dot:node(ids[l], info(l.m))
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
	  a(l.f)

	  -- restore graph state
	  dot = old

	  -- return the input to the apply
	  return ids[l.x]
   end
   
   a(l)

   dot:write('dbg/graph.dot')
end

local function r_graph_view(l)
   local dot = Graphviz()

   local function typestr(t)
	  if t.generator == 'Handshake' then
		 return tostring(t.params.A)
	  elseif t.generator == 'RV' then
		 return tostring(t.params.A)
	  elseif t.kind == 'tuple' then
		 local res = '{'
		 print(inspect(t, {depth = 2}))
		 for i,v in ipairs(t.list) do
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
		 assert(info[node.kind], "dispatch function info." .. node.kind .. " is nil")
		 return info[node.kind](node)
	  end
   }
   setmetatable(info, info_mt)

   function info.crop(m)
	  return 'crop' .. '\\n' .. '{' .. m.L .. ',' .. m.R .. ',' .. m.B .. ',' .. m.Top .. '}'
   end

   function info.lift(m)
	  return info[m.generator] and info[m.generator](m) or m.generator
   end

   info['C.cast'] = function(m)
	  return 'cast' .. '\\n' .. typestr(m.inputType) .. '\\n' .. typestr(m.outputType)
   end

   info['C.sum'] = function(m)
	  return '+'
   end

   info['C.multiply'] = function(m)
	  return '*'
   end

   info['C.broadcast'] = function(m)
   	  return 'broadcast' .. '\\n' .. '{' .. m.outputType.size[1] .. ',' .. m.outputType.size[2] .. '}'
   end

   function info.liftHandshake(m)
	  return info(m.fn)
   end

   function info.waitOnInput(m)
	  return info(m.fn)
   end
   
   function info.makeHandshake(m)
	  return info(m.fn)
   end

   function info.liftDecimate(m)
	  return info(m.fn)
   end

   function info.apply(m)
	  return info(m.fn)
   end

   function info.unpackStencil(m)
	  return 'unpackStencil'
   end

   function info.packTuple(m)
	  return 'packTuple'
   end

   function info.padSeq(m)
	  return 'padSeq'
   end

   function info.constSeq(m)
	  return 'constSeq' .. '\\n' .. typestr(m.outputType)
   end

   function info.lambda(m)
	  return info[m.generator] and info[m.generator](m) or info(m.output)
   end

   info['rigel.cropSeq'] = function(m)
	  return 'cropSeq'
   end

   function info.changeRate(m)
	  return 'changeRate' .. '\\n' .. typestr(m.inputType) .. '\\n' .. typestr(m.outputType)
   end

   function info.SoAtoAoS(m)
	  return 'zip'
   end
   
   function info.reduce(m)
   	  return 'reduce' .. '(' .. info(m.fn) .. ')'
   end

   function info.map(m)
   	  return 'map' .. '(' .. info(m.fn) .. ')'
   end

   function info.pad(m)
	  return 'pad' .. '\\n' .. '{' .. m.L .. ',' .. m.R .. ',' .. m.B .. ',' .. m.Top .. '}'
   end

   function info.stencil(m)
   	  return 'stencil' .. '\\n' .. '{' .. m.xmin .. ',' .. m.ymin .. ',' .. m.xmax .. ',' .. m.ymax .. '}'
   end

   -- generate graph from nodes
   local a = {}
   local a_mt = {
	  __call = function(a, node)
		 assert(a[node.kind], "dispatch function a." .. node.kind .. " is nil")
		 return a[node.kind](node)
	  end
   }
   setmetatable(a, a_mt)

   function a.apply(l)
	  local HIDE_CAST = true
	  if HIDE_CAST then
		 if string.find(info(l.fn), 'cast') == 1 then
			a(l.inputs[1])
			return ids[l.inputs[1]]
		 end
		 
		 dot:node(ids[l], info(l.fn))

		 if l.inputs[1] then
			dot:edge(a(l.inputs[1]), ids[l], str(typestr(l.inputs[1].type)))
		 end
		 return ids[l]
	  else
		 dot:node(ids[l], info(l.fn))

		 if l.inputs[1] then
			a(l.inputs[1])
			dot:edge(ids[l.inputs[1]], ids[l], str(typestr(l.inputs[1].type)))
		 end
		 return ids[l]
	  end
   end

   function a.concat(l)
   	  dot:node(ids[l], l.kind)
   	  for _,v in ipairs(l.inputs) do
   		 a(v)
   		 dot:edge(ids[v], ids[l], str(typestr(v.type)))
   	  end
	  
   	  return ids[l]
   end

   function a.input(l)
   	  dot:node(ids[l], l.kind.. '\\n' .. typestr(l.type))
   	  return ids[l]
   end

   function a.constant(l)
   	  dot:node(ids[l], l.kind .. '\\n' .. typestr(l.type))
   	  return ids[l]
   end

   function a.lambda(l)
	  local input = dot:node(ids[l.input], l.input.kind)
	  input.shape = 'Mdiamond'

	  -- save graph state
	  local old = dot

	  -- move into a cluster subgraph
	  dot = dot:subgraph('cluster_' .. ids[l])

	  -- generate lambda body
	  a(l.output)

	  -- restore graph state
	  dot = old

	  -- return the input to the apply
	  return ids[l.input]
   end

   a(l)

   dot:write('dbg/graph.dot')
end

local function graph_view(g)
   if g.kind == 'wrapped' then
	  b_graph_view(g)
   else
	  r_graph_view(g)
   end
end

return graph_view
