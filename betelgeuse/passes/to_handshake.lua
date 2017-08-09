local R = require 'rigelSimple'
local C = require 'examplescommon'

local function is_handshake(t)
   if t:isNamed() and t.generator == 'Handshake' then
	  return true
   elseif t.kind == 'tuple' and is_handshake(t.list[1]) then
	  return true
   end
   
   return false
end

-- converts a module to be handshaked
local function to_handshake(m)
   local t_in, w_in, h_in
   if is_handshake(m.inputType) then
	  return m
   end
   
   local hs_in = R.input(R.HS(m.inputType))

   -- inline the top level of the module
   local hs_out = m.output:visitEach(function(cur, inputs)
   		 if cur.kind == 'input' then
   			return hs_in
   		 elseif cur.kind == 'constant' then
			-- @todo: this is sort of hacky... convert to HS constseq shift by 0
			local const = R.connect{
			   input = nil,
			   toModule = R.HS(
				  R.modules.constSeq{
					 type = R.array2d(cur.type, 1, 1),
					 P = 1,
					 value = { cur.value }
				  }
			   )
			}

			return R.connect{
			   input = const,
			   toModule = R.HS(
				  C.cast(
					 R.array2d(cur.type, 1, 1),
					 cur.type
				  )
			   )
			}
		 elseif cur.kind == 'apply' then
			if inputs[1].type.kind == 'tuple' then
			   return R.connect{
				  input = R.fanIn(inputs[1].inputs),
				  toModule = R.HS(cur.fn)
			   }
			else
			   return R.connect{
				  input = inputs[1],
				  toModule = R.HS(cur.fn)
			   }
			end
		 elseif cur.kind == 'concat' then
			return R.concat(inputs)
		 end
   end)
   
   return R.defineModule{
	  input = hs_in,
	  output = hs_out
   }
end

return to_handshake
