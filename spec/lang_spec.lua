local l = require 'lang'
local inspect = require 'inspect'

describe('test', function()
			it('tests construction of an image', function()
				  local test_t = array2d(array2d(uint32(), 3, 3), 1920, 1080)
				  -- print(inspect(test_t))
				  -- print_type(test_t)

				  local I = l.array2d(l.uint32(), 1920, 1080)
				  -- print(inspect(I))

				  -- print(inspect(stencil()))
				  -- print(inspect(apply(stencil(), {I = I, w = 3, h = 3})))

				  -- print_type(stencil())
				  -- print_type(apply(stencil(), {I = I, w = 3, h = 3}))

				  -- print(inspect(apply(stencil(), { I = I, w = 3, h = 3 })))
				  -- print(inspect(apply(map(map(mul())), apply(stencil(), { I = I, w = 3, h = 3 }))))

				  local test = map(map(mul()))
				  setmetatable(test, { __call = function(t, args) return apply(t, args) end })
				  -- print(inspect(test(apply(stencil(), { I = I, w = 3, h = 3 }))))
			end)
end)
