local t, n = {}, 0
for i = 1, 100000 do t[i] = string.rep("x", 1048576) .. i; n = i end
texio.write_nl("PROBE: allocated " .. n .. " MB")
