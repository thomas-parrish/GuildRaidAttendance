--------------------------------------------
-- LibPixelPerfect
-- fyhcslb 2017-09-23 11:00:00
-- http://wow.gamepedia.com/UI_Scale
-- http://www.wowinterface.com/forums/showthread.php?t=31813
-- FULLSCREEN ONLY!!!
--------------------------------------------
local lib = LibStub:NewLibrary("LibPixelPerfect", "1.0")
if not lib then return end

function lib:GetResolution()
	-- local res = select(GetCurrentResolution(), GetScreenResolutions())
	-- local hRes, vRes = string.split("x", res)
	return string.match(({GetScreenResolutions()})[GetCurrentResolution()], "(%d+)x(%d+)")
end

-- The UI Scale goes from 1 to 0.64. 
-- At 768y we see pixel-per-pixel accurate representation of our texture, 
-- and again at 1200y if at 0.64 scale.
function lib:GetPixelPerfectScale()
	local hRes, vRes = lib:GetResolution()
	return 768/vRes
end

-- scale perfect!
function lib:PixelPerfectScale(frame)
	frame:SetScale(lib:GetPixelPerfectScale())
end

-- position perfect!
function lib:PixelPerfectPoint(frame)
	local left, bottom = frame:GetRect()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", math.floor(left + .5), math.floor(bottom + .5))
end

-- DISPLAY_SIZE_CHANGED