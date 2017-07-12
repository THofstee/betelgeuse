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

--[[
   Examples
--]]
describe('some examples', function()
			local L = require 'lang'

			it('add constant to image (broadcast)', function()
				  local im_size = { 1920, 1080 }
				  local I = input(array2d(uint8(), im_size[1], im_size[2]))
				  local c = const(uint8(), 1)
				  local bc = broadcast(im_size[1], im_size[2])(c)
				  local m = map(add())(zip_rec()(concat(I, bc)))
			end)

			it('add constant to image (lambda)', function()
				  local im_size = { 32, 16 }
				  local const_val = 30
				  local I = input(array2d(uint8(), im_size[1], im_size[2]))
				  local x = input(uint8())
				  local c = const(uint8(), const_val)
				  local add_c = lambda(add()(concat(x, c)), x)
				  local m_add = map(add_c)
			end)

			it('add two image streams', function()
				  local im_size = { 1920, 1080 }
				  local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
				  local J = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
				  local ij = L.zip_rec()(L.concat(I, J))
				  local m = L.map(L.add())(ij)
			end)

			it('convolution', function()
				  local im_size = { 1920, 1080 }
				  local pad_size = { 1920+16, 1080+3 }
				  local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
				  local pad = L.pad(8, 8, 2, 1)(I)
				  local st = L.stencil(-1, -1, 4, 4)(pad)
				  local taps = L.const(L.array2d(L.uint8(), 4, 4), {
										  {  4, 14, 14,  4 },
										  { 14, 32, 32, 14 },
										  { 14, 32, 32, 14 },
										  {  4, 14, 14,  4 }})
				  local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
				  local st_wt = L.zip_rec()(L.concat(st, wt))
				  local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
				  local m = conv(st_wt)
				  local m2 = L.map(L.reduce(L.add()))(L.map(L.map(L.mul()))(st_wt))
			end)

			describe('files in the examples directory', function()
				  local lfs = require 'lfs'
				  local dir = lfs.currentdir() .. '/examples/'
				  for iter, dir_obj in lfs.dir(dir) do
					 if string.find(iter, '.lua') then
						it(iter, function()
							  dofile(dir .. iter)
						end)
					 end
				  end
			end)
end)
