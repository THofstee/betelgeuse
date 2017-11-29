--[[
   Library Utility Tests
--]]
describe('loading #lib', function()
            insulate(function()
                  it('tests undeclared variable use', function()
                        assert.has_no.errors(function()
                              require 'strict'
                              require 'betelgeuse.lang'
                        end)
                  end)
            end)

            insulate(function()
                  it('tests global namespace leaking', function()
                        _G.__EXTRASTRICT = true
                        assert.has_no.errors(function()
                              require 'strict'
                              require 'betelgeuse.lang'
                        end)
                  end)
            end)
end)

--[[
   Library Usage Tests
--]]
describe('usage #lib', function()
            local L = require 'betelgeuse.lang'
            L.import()

            --[[
               Value Tests
            --]]
            describe('input #value', function()
                        it('tests that input is not memoized', function()
                              local a = input(fixed(32, 0))
                              local b = input(fixed(32, 0))
                              assert.are.same(a, b)
                              assert.are_not.equal(a, b)
                        end)
            end)

            --[[
               Module Tests
            --]]
            describe('map #module', function()
                        it('tests map type checking', function()
                              local t = concat(input(fixed(32, 0)), input(fixed(32, 0)))
                              assert.has_error(function()
                                    map(mul())(t)
                              end)
                        end)

                        it('tests map', function()
                              local t = zip()(concat(input(array2d(fixed(32, 0), 13, 13)), input(array2d(fixed(32, 0), 13, 13))))
                              assert.has_no.errors(function()
                                    map(mul())(t)
                              end)
                        end)
            end)


            describe('reduce #module', function()
                        it('tests reduce type checking', function()
                              local t = input(fixed(32, 0))
                              assert.has_error(function()
                                    reduce(mul())(t)
                              end)
                        end)

                        it('tests reduce', function()
                              local t = input(array2d(fixed(32, 0), 13, 13))
                              assert.has_no.errors(function()
                                    reduce(mul())(t)
                              end)
                        end)
            end)

            describe('lambda #module', function()
                        it('tests lambda', function()
                              local x = input(fixed(32, 0))
                              local y = add()(concat(x, const(fixed(32, 0), 4)))
                              local f = lambda(y, x)
                              local z = f(const(fixed(32, 0), 1))
                              assert.are.same(z.type, fixed(32, 0))
                        end)
            end)

            --[[
               Helper Tests
            --]]
            describe('zip_rec', function()
                        it('tests zip_rec 1-deep', function()
                              -- ([uint32], [uint32]) -> [(uint32, uint32)]
                              -- ((uncurry zip) (a, b))
                              local a = input(array2d(fixed(8, 0), 3, 3))
                              local b = input(array2d(fixed(8, 0), 3, 3))
                              local c = zip()(concat(a, b))
                              local d = zip_rec()(concat(a, b))
                              assert.are.same(c.type, d.type)
                        end)

                        it('tests zip_rec 2-deep', function()
                              -- ([[uint8]], [[uint8]]) -> [[(uint8, uint8)]]
                              -- (map (uncurry zip) ((uncurry zip) (a, b)))
                              local a = input(array2d(array2d(fixed(8, 0), 3, 3), 5, 5))
                              local b = input(array2d(array2d(fixed(8, 0), 3, 3), 5, 5))
                              local c = map(zip())(zip()(concat(a, b)))
                              local d = zip_rec()(concat(a, b))
                              assert.are.same(c.type, d.type)
                        end)

                        it('tests zip_rec 3-deep', function()
                              -- ([[[uint8]]], [[[uint8]]]) -> [[[(uint8, uint8)]]]
                              -- (map (map (uncurry zip)) (map (uncurry zip) ((uncurry zip) (a, b))))
                              local a = input(array2d(array2d(array2d(fixed(8, 0), 3, 3), 5, 5), 7, 7))
                              local b = input(array2d(array2d(array2d(fixed(8, 0), 3, 3), 5, 5), 7, 7))
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
            local L = require 'betelgeuse.lang'
            L.import()

            it('add constant to image (broadcast)', function()
                  local im_size = { 1920, 1080 }
                  local I = input(array2d(fixed(8, 0), im_size[1], im_size[2]))
                  local c = const(fixed(8, 0), 1)
                  local bc = broadcast(im_size[1], im_size[2])(c)
                  local m = map(add())(zip_rec()(concat(I, bc)))
            end)

            it('add constant to image (lambda)', function()
                  local im_size = { 32, 16 }
                  local const_val = 30
                  local I = input(array2d(fixed(8, 0), im_size[1], im_size[2]))
                  local x = input(fixed(8, 0))
                  local c = const(fixed(8, 0), const_val)
                  local add_c = lambda(add()(concat(x, c)), x)
                  local m_add = map(add_c)
            end)

            it('add two image streams', function()
                  local im_size = { 1920, 1080 }
                  local I = input(array2d(fixed(8, 0), im_size[1], im_size[2]))
                  local J = input(array2d(fixed(8, 0), im_size[1], im_size[2]))
                  local ij = zip_rec()(concat(I, J))
                  local m = map(add())(ij)
            end)

            it('convolution', function()
                  local im_size = { 1920, 1080 }
                  local pad_size = { 1920+16, 1080+3 }
                  local I = input(array2d(fixed(8, 0), im_size[1], im_size[2]))
                  local pad = pad(8, 8, 2, 1)(I)
                  local st = stencil(-1, -1, 4, 4)(pad)
                  local taps = const(array2d(fixed(8, 0), 4, 4), {
                                        {  4, 14, 14,  4 },
                                        { 14, 32, 32, 14 },
                                        { 14, 32, 32, 14 },
                                        {  4, 14, 14,  4 }})
                  local wt = broadcast(pad_size[1], pad_size[2])(taps)
                  local st_wt = zip_rec()(concat(st, wt))
                  local conv = chain(map(map(mul())), map(reduce(add())))
                  local m = conv(st_wt)
                  local m2 = map(reduce(add()))(map(map(mul()))(st_wt))
            end)

end)
