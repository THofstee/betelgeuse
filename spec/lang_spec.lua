local l = require 'lang'

describe('test', function()
			it('tests construction of an image', function()
				  l.import()
				  local test_t = array2d(array2d(uint32(), 3, 3), 1920, 1080)
				  local I = l.array2d(l.uint32(), 1920, 1080)
				  local test = map(map(mul()))
			end)
end)
