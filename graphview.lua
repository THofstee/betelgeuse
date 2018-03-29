local Graphviz = require 'graphviz'
local memoize = require 'memoize'

local G = {}
G.render = true

local function graph_view(g)
   if g.kind == 'wrapped' then
      require'graphview.betelgeuse'(g)
   elseif g.tag == 'rigel' then
      require'graphview.rigel'(g)
   else
      require'graphview.ir'(g)
   end
end

local G_mt = {
   __call = function(t, g)
      graph_view(g)
   end
}

setmetatable(G, G_mt)
return G
