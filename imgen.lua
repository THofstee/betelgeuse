local out = io.open('out.raw', 'wb')

-- impulse response
-- local im_size = { 32, 32 }
-- for i=1,im_size[1] do
--    for j=1,im_size[2] do
--       if i == 1 and j == 1 then
--          out:write(string.char(0xff))
--       else
--          out:write(string.char(0x00))
--       end
--    end
-- end

-- some sort of white squares
-- local im_size = { 256, 256 }
-- for i=1,im_size[1] do
--    for j=1,im_size[2] do
--       if (i-5)%16 < 8 and (j-5)%16 < 8 then
--          out:write(string.char(0xff))
--       else
--          out:write(string.char(0x00))
--       end
--    end
-- end

-- grid
local im_size = { 256, 256 }
for i=1,im_size[1] do
   for j=1,im_size[2] do
      if (i-10)%16 < 14 and (j-10)%16 < 14 then
         out:write(string.char(0x00))
      else
         out:write(string.char(0xff))
      end
   end
end

-- write to raw
out:close()

-- write to png
local size_str = im_size[1] .. 'x' .. im_size[2] .. '+0'
os.execute('convert -flip -depth 8 -size ' .. size_str .. ' gray:out.raw out.png')
