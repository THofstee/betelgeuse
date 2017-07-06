--[[
   Library Utility Tests
--]]
describe('loading #lib', function()
			insulate(function()
				  it('tests undeclared variable use', function()
						assert.has_no.errors(function()
							  require 'strict'
							  require 'lang'
						end)
				  end)
			end)

			insulate(function()
				  it('tests global namespace leaking', function()
						_G.__EXTRASTRICT = true
						assert.has_no.errors(function()
							  require 'strict'
							  require 'lang'
						end)
				  end)
			end)
end)

--[[
   Library Usage Tests
--]]
describe('usage #lib', function()
			local L = require 'lang'
			
			--[[
			   Value Tests
			--]]
			describe('input #value', function()
						L.import()

						it('tests that input is not memoized', function()
							  local a = input(uint32())
							  local b = input(uint32())
							  assert.are.same(a, b)
							  assert.are_not.equal(a, b)
						end)
			end)

			--[[
			   Module Tests
			--]]
			describe('map #module', function()
						L.import()

						it('tests map type checking', function()
							  local t = concat(input(uint32()), input(uint32()))
							  assert.has_error(function()
									map(mul())(t)
							  end)
						end)

						it('tests map', function()
							  local t = zip()(concat(input(array2d(uint32(), 13, 13)), input(array2d(uint32(), 13, 13))))
							  assert.has_no.errors(function()
									map(mul())(t)
							  end)
						end)
			end)


			describe('reduce #module', function()
						L.import()

						it('tests reduce type checking', function()
							  local t = input(uint32())
							  assert.has_error(function()
									reduce(mul())(t)
							  end)
						end)

						it('tests reduce', function()
							  local t = input(array2d(uint32(), 13, 13))
							  assert.has_no.errors(function()
									reduce(mul())(t)
							  end)
						end)
			end)

			describe('lambda #module', function()
						it('tests lambda', function()
							  local x = input(uint32())
							  local y = add()(concat(x, const(uint32(), 4)))
							  local f = lambda(y, x)
							  local z = f(const(uint32(), 1))
							  assert.are.same(z.type, uint32())
						end)
			end)

			--[[
			   Helper Tests
			--]]
			describe('zip_rec', function()
						L.import()

						it('tests zip_rec 1-deep', function()
							  -- ([uint32], [uint32]) -> [(uint32, uint32)]
							  -- ((uncurry zip) (a, b))
							  local a = input(array2d(uint8(), 3, 3))
							  local b = input(array2d(uint8(), 3, 3))
							  local c = zip()(concat(a, b))
							  local d = zip_rec()(concat(a, b))
							  assert.are.same(c.type, d.type)
						end)

						it('tests zip_rec 2-deep', function()
							  -- ([[uint8]], [[uint8]]) -> [[(uint8, uint8)]]
							  -- (map (uncurry zip) ((uncurry zip) (a, b)))
							  local a = input(array2d(array2d(uint8(), 3, 3), 5, 5))
							  local b = input(array2d(array2d(uint8(), 3, 3), 5, 5))
							  local c = map(zip())(zip()(concat(a, b)))
							  local d = zip_rec()(concat(a, b))
							  assert.are.same(c.type, d.type)
						end)

						it('tests zip_rec 3-deep', function()
							  -- ([[[uint8]]], [[[uint8]]]) -> [[[(uint8, uint8)]]]
							  -- (map (map (uncurry zip)) (map (uncurry zip) ((uncurry zip) (a, b))))
							  local a = input(array2d(array2d(array2d(uint8(), 3, 3), 5, 5), 7, 7))
							  local b = input(array2d(array2d(array2d(uint8(), 3, 3), 5, 5), 7, 7))
							  local c = map(map(zip()))(map(zip())(zip()(concat(a, b))))
							  local d = zip_rec()(concat(a, b))
							  assert.are.same(c.type, d.type)
						end)
			end)
end)
