local L = require 'lang'

describe('test', function()
			it('tests zip_rec', function()
				  L.import()

				  -- ([uint32], [uint32]) -> [(uint32, uint32)]
				  -- ((uncurry zip) (a, b))
				  local a = input(array2d(uint8(), 3, 3))
				  local b = input(array2d(uint8(), 3, 3))
				  local c = zip()(concat(a, b))
				  local d = zip_rec()(concat(a, b))
				  assert(tostring(c.type) == tostring(d.type))

				  -- ([[uint8]], [[uint8]]) -> [[(uint8, uint8)]]
				  -- (map (uncurry zip) ((uncurry zip) (a, b)))
				  local a = input(array2d(array2d(uint8(), 3, 3), 5, 5))
				  local b = input(array2d(array2d(uint8(), 3, 3), 5, 5))
				  local c = map(zip())(zip()(concat(a, b)))
				  local d = zip_rec()(concat(a, b))
				  assert(tostring(c.type) == tostring(d.type))

				  -- ([[[uint8]]], [[[uint8]]]) -> [[[(uint8, uint8)]]]
				  -- (map (map (uncurry zip)) (map (uncurry zip) ((uncurry zip) (a, b))))
				  local a = input(array2d(array2d(array2d(uint8(), 3, 3), 5, 5), 7, 7))
				  local b = input(array2d(array2d(array2d(uint8(), 3, 3), 5, 5), 7, 7))
				  local c = map(map(zip()))(map(zip())(zip()(concat(a, b))))
				  local d = zip_rec()(concat(a, b))
				  assert(tostring(c.type) == tostring(d.type))
			end)
end)
