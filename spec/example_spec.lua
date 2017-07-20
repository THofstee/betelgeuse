local lfs = require 'lfs'
local dir = lfs.currentdir() .. '/examples/'

describe('tests in the examples directory', function()
			for iter, dir_obj in lfs.dir(dir) do
			   if string.find(iter, '.lua') then
				  insulate(
					 function() it(iter, function()
									  dofile(dir .. iter)
								  end)
				  end)
			   end
			end
end)
