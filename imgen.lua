local im_size = { 32, 32 }
local out = io.open('out.raw', 'wb')

for channel=1,3 do
   for i=1,im_size[1] do
	  for j=1,im_size[2] do
		 if i == 1 and j == 1 then
			out:write(string.char(0x01))
		 else
			out:write(string.char(0x00))
		 end
	  end
   end
end

out:close()
