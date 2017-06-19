local inspect = require 'inspect'
local asdl = require 'asdl'

local T = asdl.NewContext()
T:Define [[
Type = uint32
     | tuple(Type a, Type b)
     | array(Type t, number n)
     | array2d(Type t, number w, number h)

Val = number

Var = input(Type t)
    | const(Type t, Val v)
    | placeholder(Type t)
    | concat(Var a, Var b)
#    | split(Var v) # does this need to exist?
    | apply(Module m, Var v)

Module = mul
       | map(Module m)
       | reduce(Module m)
       | zip
#       | broadcast # needds additional parameters
#       | lift # dont know how to treat this yet
       | chain(Module a, Module b)

# Connect(Var v, Var placeholder)
]]

-- In theory, we can do something like chain(map(*), reduce(+)) for a conv
-- @todo: maybe add a zip_rec function that recursively zip until primitive types

-- print(inspect(T))
print(inspect(T.Type))
