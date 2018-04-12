local Graphviz = require 'graphviz'

local bg = require 'graphview.betelgeuse'
local ri = require 'graphview.rigel'
local ir = require 'graphview.ir'

local G = {}
G.render = true

local function graph_view(g)
   if g.kind == 'wrapped' then
      bg(g)
   elseif g.tag == 'rigel' then
      ri(g)
   else
      ir(g)
   end
end

local G_mt = {
   __call = function(t, g)
      graph_view(g)
   end
}

setmetatable(G, G_mt)
return G
