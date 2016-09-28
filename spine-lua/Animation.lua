-------------------------------------------------------------------------------
-- Spine Runtimes Software License
-- Version 2.3
-- 
-- Copyright (c) 2013-2015, Esoteric Software
-- All rights reserved.
-- 
-- You are granted a perpetual, non-exclusive, non-sublicensable and
-- non-transferable license to use, install, execute and perform the Spine
-- Runtimes Software (the "Software") and derivative works solely for personal
-- or internal use. Without the written permission of Esoteric Software (see
-- Section 2 of the Spine Software License Agreement), you may not (a) modify,
-- translate, adapt or otherwise create derivative works, improvements of the
-- Software or develop new applications using the Software or (b) remove,
-- delete, alter or obscure any trademarks or any copyright, trademark, patent
-- or other intellectual property or proprietary rights notices on or in the
-- Software, including any copy thereof. Redistributions in binary or source
-- form must include this license and terms.
-- 
-- THIS SOFTWARE IS PROVIDED BY ESOTERIC SOFTWARE "AS IS" AND ANY EXPRESS OR
-- IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
-- EVENT SHALL ESOTERIC SOFTWARE BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-------------------------------------------------------------------------------

-- FIXME
-- All the indexing in this file is zero based. We use zlen()
-- instead of the # operator. Initialization of number arrays
-- is performed via utils.newNumberArrayZero. This needs
-- to be rewritten using one-based indexing for better performance

local utils = require "spine-lua.utils"

local function zlen(array)
  return #array + 1
end

local Animation = {}
function Animation.new (name, timelines, duration)
	if not timelines then error("timelines cannot be nil", 2) end

	local self = {
		name = name,
		timelines = timelines,
		duration = duration
	}

	function self:apply (skeleton, lastTime, time, loop, events)
		if not skeleton then error("skeleton cannot be nil.", 2) end

		if loop and duration > 0 then
			time = time % self.duration
			if lastTime > 0 then lastTime = lastTime % self.duration end
		end

		for i,timeline in ipairs(self.timelines) do
			timeline:apply(skeleton, lastTime, time, events, 1)
		end
	end

	function self:mix (skeleton, lastTime, time, loop, events, alpha)
		if not skeleton then error("skeleton cannot be nil.", 2) end

		if loop and duration > 0 then
			time = time % self.duration
			if lastTime > 0  then lastTime = lastTime % self.duration end
		end

		for i,timeline in ipairs(self.timelines) do
			timeline:apply(skeleton, lastTime, time, events, alpha)
		end
	end

	return self
end

local function binarySearch (values, target, step)
	local low = 0
	local high = math.floor(zlen(values) / step - 2)
	if high == 0 then return step end
	local current = math.floor(high / 2)
	while true do
		if values[(current + 1) * step] <= target then
			low = current + 1
		else
			high = current
		end
		if low == high then return (low + 1) * step end
		current = math.floor((low + high) / 2)
	end
end

local function binarySearch1 (values, target)
	local low = 0
	local high = math.floor(zlen(values)  - 2)
	if high == 0 then return 1 end
	local current = math.floor(high / 2)
	while true do
		if values[current + 1] <= target then
			low = current + 1
		else
			high = current
		end
		if low == high then return low + 1 end
		current = math.floor((low + high) / 2)
	end
end

local function linearSearch (values, target, step)
  local i = 0
  local last = zlen(values) - step
  while i <= last do
		if (values[i] > target) then return i end
    i = i + step
	end
	return -1
end

Animation.CurveTimeline = {}
function Animation.CurveTimeline.new (frameCount)
	local LINEAR = 0
	local STEPPED = 1
	local BEZIER = 2;
	local BEZIER_SIZE = 10 * 2 - 1

	local self = {
		curves = utils.newNumberArrayZero((frameCount - 1) * BEZIER_SIZE) -- type, x, y, ...
	}
  
  function self:getFrameCount ()
    return math.floor(zlen(self.curves) / BEZIER_SIZE) + 1
  end

	function self:setLinear (frameIndex)
		self.curves[frameIndex * BEZIER_SIZE] = LINEAR
	end

	function self:setStepped (frameIndex)
		self.curves[frameIndex * BEZIER_SIZE] = STEPPED
	end
  
  function self:getCurveType (frameIndex)
    local index = frameIndex * BEZIER_SIZE
    if index == zlen(self.curves) then return LINEAR end
    local type = self.curves[index]
    if type == LINEAR then return LINEAR end
    if type == STEPPED then return STEPPED end
    return BEZIER
  end

	function self:setCurve (frameIndex, cx1, cy1, cx2, cy2)
			local tmpx = (-cx1 * 2 + cx2) * 0.03
      local tmpy = (-cy1 * 2 + cy2) * 0.03
			local dddfx = ((cx1 - cx2) * 3 + 1) * 0.006
      local dddfy = ((cy1 - cy2) * 3 + 1) * 0.006
			local ddfx = tmpx * 2 + dddfx
      local ddfy = tmpy * 2 + dddfy
			local dfx = cx1 * 0.3 + tmpx + dddfx * 0.16666667
      local dfy = cy1 * 0.3 + tmpy + dddfy * 0.16666667

			local i = frameIndex * BEZIER_SIZE
			local curves = self.curves
			curves[i] = BEZIER;
      i = i + 1

			local x = dfx
      local y = dfy
      local n = i + BEZIER_SIZE - 1
      while i < n do
				curves[i] = x
				curves[i + 1] = y
				dfx = dfx + ddfx
				dfy = dfy + ddfy
				ddfx = ddfx + dddfx
				ddfy = ddfy + dddfy
				x = x + dfx
				y = y + dfy
        i = i + 2
			end
	end

	function self:getCurvePercent (frameIndex, percent)
    percent = utils.clamp(percent, 0, 1)
		local curves = self.curves
		local i = frameIndex * BEZIER_SIZE
		local type = curves[i]
		if type == LINEAR then return percent end
		if type == STEPPED then return 0 end
		i = i + 1
		local x
		local n = i + BEZIER_SIZE - 1
		local start = i
		while i < n do
			x = curves[i]
			if x >= percent then
				local prevX, prevY
				if i == start then
					prevX = 0
					prevY = 0
				else
					prevX = curves[i - 2]
					prevY = curves[i - 1]
				end
				return prevY + (curves[i + 1] - prevY) * (percent - prevX) / (x - prevX)
			end
			i = i + 2
		end
		local y = curves[i - 1]
		return y + (1 - y) * (percent - x) / (1 - x) -- Last point is 1,1.
	end

	return self
end

Animation.RotateTimeline = {}
Animation.RotateTimeline.ENTRIES = 2
function Animation.RotateTimeline.new (frameCount)
  local ENTRIES = Animation.RotateTimeline.ENTRIES
	local PREV_TIME = -2
  local PREV_ROTATION = -1
	local ROTATION = 1

	local self = Animation.CurveTimeline.new(frameCount)
	self.boneIndex = -1
  self.frames = utils.newNumberArrayZero(frameCount * 2)
  
	function self:setFrame (frameIndex, time, degrees)
		frameIndex = frameIndex * 2
		self.frames[frameIndex] = time
		self.frames[frameIndex + ROTATION] = degrees
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local bone = skeleton.bones[self.boneIndex]

		if time >= frames[zlen(frames) - ENTRIES] then -- Time is after last frame.
			local amount = bone.data.rotation + frames[zlen(frames) + PREV_ROTATION] - bone.rotation
			while amount > 180 do
				amount = amount - 360
			end
			while amount < -180 do
				amount = amount + 360
			end
			bone.rotation = bone.rotation + amount * alpha
			return
		end

		-- Interpolate between the last frame and the current frame.
		local frame = binarySearch(frames, time, ENTRIES)
		local prevRotation = frames[frame + PREV_ROTATION]
		local frameTime = frames[frame]
    local percent = self:getCurvePercent((math.floor(frame / 2)) - 1, 1 - (time - frameTime) / (frames[frame + PREV_TIME] - frameTime));

		local amount = frames[frame + ROTATION] - prevRotation
		while amount > 180 do
			amount = amount - 360
		end
		while amount < -180 do
			amount = amount + 360
		end
		amount = bone.data.rotation + (prevRotation + amount * percent) - bone.rotation
		while amount > 180 do
			amount = amount - 360
		end
		while amount < -180 do
			amount = amount + 360
		end
		bone.rotation = bone.rotation + amount * alpha
	end

	return self
end

Animation.TranslateTimeline = {}
Animation.TranslateTimeline.ENTRIES = 3
function Animation.TranslateTimeline.new (frameCount)
  local ENTRIES = Animation.TranslateTimeline.ENTRIES
	local PREV_TIME = -3
  local PREV_X = -2
  local PREV_Y = -1
	local X = 1
	local Y = 2

	local self = Animation.CurveTimeline.new(frameCount)
  self.frames = utils.newNumberArrayZero(frameCount * ENTRIES)
	self.boneIndex = -1

	function self:setFrame (frameIndex, time, x, y)
		frameIndex = frameIndex * ENTRIES
		self.frames[frameIndex] = time
		self.frames[frameIndex + X] = x
		self.frames[frameIndex + Y] = y
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local bone = skeleton.bones[self.boneIndex]
		
		if time >= frames[zlen(frames) - ENTRIES] then -- Time is after last frame.
			bone.x = bone.x + (bone.data.x + frames[zlen(frames) + PREV_X] - bone.x) * alpha
			bone.y = bone.y + (bone.data.y + frames[zlen(frames) + PREV_Y] - bone.y) * alpha
			return
		end

		-- Interpolate between the last frame and the current frame.
		local frame = binarySearch(frames, time, ENTRIES)
		local prevX = frames[frame + PREV_X]
		local prevY = frames[frame + PREV_Y]
		local frameTime = frames[frame]
		local percent = self:getCurvePercent(math.floor(frame / ENTRIES) - 1, 1 - (time - frameTime) / (frames[frame + PREV_TIME] - frameTime))

		bone.x = bone.x + (bone.data.x + prevX + (frames[frame + X] - prevX) * percent - bone.x) * alpha
		bone.y = bone.y + (bone.data.y + prevY + (frames[frame + Y] - prevY) * percent - bone.y) * alpha
	end

	return self
end

Animation.ScaleTimeline = {}
Animation.ScaleTimeline.ENTRIES = Animation.TranslateTimeline.ENTRIES
function Animation.ScaleTimeline.new (frameCount)
  local ENTRIES = Animation.ScaleTimeline.ENTRIES
	local PREV_TIME = -3
  local PREV_X = -2
  local PREV_Y = -1
	local X = 1
	local Y = 2

	local self = Animation.TranslateTimeline.new(frameCount)

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local bone = skeleton.bones[self.boneIndex]

		if time >= frames[zlen(frames) - ENTRIES] then -- Time is after last frame.
			bone.scaleX = bone.scaleX + (bone.data.scaleX * frames[zlen(frames) + PREV_X] - bone.scaleX) * alpha
			bone.scaleY = bone.scaleY + (bone.data.scaleY * frames[zlen(frames) + PREV_Y] - bone.scaleY) * alpha
			return
		end

		-- Interpolate between the last frame and the current frame.
		local frame = binarySearch(frames, time, ENTRIES)
		local prevX = frames[frame + PREV_X]
		local prevY = frames[frame + PREV_Y]
		local frameTime = frames[frame]
		local percent = self:getCurvePercent(math.floor(frame / ENTRIES) - 1,
				1 - (time - frameTime) / (frames[frame + PREV_TIME] - frameTime));

		bone.scaleX = bone.scaleX + (bone.data.scaleX * (prevX + (frames[frame + X] - prevX) * percent) - bone.scaleX) * alpha
		bone.scaleY = bone.scaleY + (bone.data.scaleY * (prevY + (frames[frame + Y] - prevY) * percent) - bone.scaleY) * alpha
	end

	return self
end

Animation.ShearTimeline = {}
Animation.ShearTimeline.ENTRIES = Animation.TranslateTimeline.ENTRIES
function Animation.ShearTimeline.new (frameCount)
  local ENTRIES = Animation.ShearTimeline.ENTRIES
	local PREV_TIME = -3
  local PREV_X = -2
  local PREV_Y = -1
	local X = 1
	local Y = 2

	local self = Animation.TranslateTimeline.new(frameCount)

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local bone = skeleton.bones[self.boneIndex]

		if time >= frames[zlen(frames) - ENTRIES] then -- Time is after last frame.
			bone.shearX = bone.shearX + (bone.data.shearX * frames[zlen(frames) + PREV_X] - bone.shearX) * alpha
			bone.shearY = bone.shearY + (bone.data.shearY * frames[zlen(frames) + PREV_Y] - bone.shearY) * alpha
			return
		end

		-- Interpolate between the last frame and the current frame.
		local frame = binarySearch(frames, time, ENTRIES)
		local prevX = frames[frame + PREV_X]
		local prevY = frames[frame + PREV_Y]
		local frameTime = frames[frame]
		local percent = self:getCurvePercent(math.floor(frame / ENTRIES) - 1,
				1 - (time - frameTime) / (frames[frame + PREV_TIME] - frameTime));

		bone.shearX = bone.shearX + (bone.data.shearX * (prevX + (frames[frame + X] - prevX) * percent) - bone.shearX) * alpha
		bone.shearY = bone.shearY + (bone.data.shearY * (prevY + (frames[frame + Y] - prevY) * percent) - bone.shearY) * alpha
	end

	return self
end

Animation.ColorTimeline = {}
Animation.ColorTimeline.ENTRIES = 5
function Animation.ColorTimeline.new (frameCount)
  local ENTRIES = Animation.ColorTimeline.ENTRIES
  local PREV_TIME = -5
  local PREV_R = -4
  local PREV_G = -3
  local PREV_B = -2
  local PREV_A = -1
  local R = 1
  local G = 2
  local B = 3
  local A = 4

	local self = Animation.CurveTimeline.new(frameCount)
  self.frames = utils.newNumberArrayZero(frameCount * ENTRIES)
	self.slotIndex = -1

	function self:setFrame (frameIndex, time, r, g, b, a)
		frameIndex = frameIndex * ENTRIES
		self.frames[frameIndex] = time
		self.frames[frameIndex + R] = r
		self.frames[frameIndex + G] = g
		self.frames[frameIndex + B] = b
		self.frames[frameIndex + A] = a
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local r, g, b, a
		if time >= frames[zlen(frames) - ENTRIES] then -- Time is after last frame.
      local i = zlen(frames)
			r = frames[i + PREV_R]
			g = frames[i + PREV_G]
			b = frames[i + PREV_B]
			a = frames[i + PREV_A]
		else
			-- Interpolate between the last frame and the current frame.
			local frame = binarySearch(frames, time, ENTRIES)
      r = frames[frame + PREV_R]
			g = frames[frame + PREV_G]
			b = frames[frame + PREV_B]
			a = frames[frame + PREV_A]
			local frameTime = frames[frame]
			local percent = self:getCurvePercent(math.floor(frame / ENTRIES) - 1,
					1 - (time - frameTime) / (frames[frame + PREV_TIME] - frameTime));

			r = r + (frames[frame + R] - r) * percent
			g = g + (frames[frame + G] - g) * percent
			b = b + (frames[frame + B] - b) * percent
			a = a + (frames[frame + A] - a) * percent
		end
		local color = skeleton.slots[self.slotIndex].color
		if alpha < 1 then
			color:add((r - color.r) * alpha, (g - color.g) * alpha, (b - color.b) * alpha, (a - color.a) * alpha);
		else
			color:set(r, g, b, a)
		end
	end

	return self
end

Animation.AttachmentTimeline = {}
function Animation.AttachmentTimeline.new (frameCount)
	local self = {
		frames = utils.newNumberArrayZero(frameCount), -- time, ...
		attachmentNames = {},
		slotName = nil
	}

	function self:getFrameCount ()
		return zlen(self.frames)
	end

	function self:setFrame (frameIndex, time, attachmentName)
		self.frames[frameIndex] = time
		self.attachmentNames[frameIndex] = attachmentName
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
    if time < frames[0] then return end  

		local frameIndex = 0
		if time >= frames[zlen(frames) - 1] then
			frameIndex = zlen(frames) - 1
		else
			frameIndex = binarySearch1(frames, time) - 1
		end
		if frames[frameIndex] < lastTime then return end

		local attachmentName = self.attachmentNames[frameIndex]
		local slot = skeleton.slotsByName[self.slotName]
		if attachmentName then
			if not slot.attachment then
				slot:setAttachment(skeleton:getAttachment(self.slotName, attachmentName))
			elseif slot.attachment.name ~= attachmentName then
				slot:setAttachment(skeleton:getAttachment(self.slotName, attachmentName))
			end
		else
			slot:setAttachment(nil)
		end
	end

	return self
end

Animation.EventTimeline = {}
function Animation.EventTimeline.new (frameCount)
	local self = {
		frames = utils.newNumberArrayZero(frameCount),
		events = {}
	}

	function self:getFrameCount ()
		return zlen(self.frames)
	end

	function self:setFrame (frameIndex, event)
		self.frames[frameIndex] = event.time
		self.events[frameIndex] = event
	end

	-- Fires events for frames > lastTime and <= time.
	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		if not firedEvents then return end

		local frames = self.frames
		local frameCount = zlen(frames)

		if lastTime > time then -- Fire events after last time for looped animations.
			self:apply(skeleton, lastTime, 999999, firedEvents, alpha)
			lastTime = -1
		elseif lastTime >= frames[frameCount - 1] then -- Last time is after last frame.
			return
		end
		if time < frames[0] then return end -- Time is before first frame.

		local frame
		if lastTime < frames[0] then
			frame = 0
		else
			frame = binarySearch1(frames, lastTime)
			local frame = frames[frame]
			while frame > 0 do -- Fire multiple events with the same frame.
				if frames[frame - 1] ~= frame then break end
				frame = frame - 1
			end
		end
		local events = self.events
		while frame < frameCount and time >= frames[frame] do
			table.insert(firedEvents, events[frame])
			frame = frame + 1
		end
	end

	return self
end

Animation.DrawOrderTimeline = {}
function Animation.DrawOrderTimeline.new (frameCount)
	local self = {
		frames = utils.newNumberArrayZero(frameCount),
		drawOrders = {}
	}

	function self:getFrameCount ()
		return zlen(self.frames)
	end

	function self:setFrame (frameIndex, time, drawOrder)
		self.frames[frameIndex] = time
		self.drawOrders[frameIndex] = drawOrder
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local frame
		if time >= frames[zlen(frames) - 1] then -- Time is after last frame.
			frame = zlen(frames) - 1
		else
			frame = binarySearch1(frames, time) - 1
		end

		local drawOrder = skeleton.drawOrder
		local slots = skeleton.slots
		local drawOrderToSetupIndex = self.drawOrders[frame]
		if not drawOrderToSetupIndex then
			for i,slot in ipairs(slots) do
				drawOrder[i] = slots[i]
			end
		else
			for i,setupIndex in ipairs(drawOrderToSetupIndex) do
				drawOrder[i] = skeleton.slots[setupIndex]
			end
		end
	end

	return self
end

Animation.FfdTimeline = {}
function Animation.FfdTimeline.new ()
	local self = Animation.CurveTimeline.new()
	self.frames = {} -- time, ...
	self.frameVertices = {}
	self.slotIndex = -1

	function self:getDuration ()
		return self.frames[#self.frames]
	end

	function self:getFrameCount ()
		return #self.frames + 1
	end

	function self:setFrame (frameIndex, time, vertices)
		self.frames[frameIndex] = time
		self.frameVertices[frameIndex] = vertices
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local slot = skeleton.slots[self.slotIndex]
		if slot.attachment ~= self.attachment then return end

		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local frameVertices = self.frameVertices
		local vertexCount = #frameVertices[0]
		local vertices = slot.attachmentVertices
		if not vertices or #vertices < vertexCount then
			vertices = {}
			slot.attachmentVertices = vertices
		end
		if #vertices ~= vertexCount then
			alpha = 1 -- Don't mix from uninitialized slot vertices.
		end
		slot.attachmentVerticesCount = vertexCount
		if time >= frames[#frames] then -- Time is after last frame.
			local lastVertices = frameVertices[#frames]
			if alpha < 1 then
				for i = 1, vertexCount do
					local vertex = vertices[i]
					vertices[i] = vertex + (lastVertices[i] - vertex) * alpha
				end
			else
				for i = 1, vertexCount do
					vertices[i] = lastVertices[i]
				end
			end
			return
		end

		-- Interpolate between the previous frame and the current frame.
		local frameIndex = binarySearch1(frames, time)
		local frameTime = frames[frameIndex]
		local percent = 1 - (time - frameTime) / (frames[frameIndex - 1] - frameTime)
		if percent < 0 then percent = 0 elseif percent > 1 then percent = 1 end
		percent = self:getCurvePercent(frameIndex - 1, percent)

		local prevVertices = frameVertices[frameIndex - 1]
		local nextVertices = frameVertices[frameIndex]

		if alpha < 1 then
			for i = 1, vertexCount do
				local prev = prevVertices[i]
				local vertex = vertices[i]
				vertices[i] = vertex + (prev + (nextVertices[i] - prev) * percent - vertex) * alpha
			end
		else
			for i = 1, vertexCount do
				local prev = prevVertices[i]
				vertices[i] = prev + (nextVertices[i] - prev) * percent
			end
		end
	end

	return self
end

Animation.IkConstraintTimeline = {}
function Animation.IkConstraintTimeline.new ()
	local PREV_FRAME_TIME = -3
	local PREV_FRAME_MIX = -2
	local PREV_FRAME_BEND_DIRECTION = -1
	local FRAME_MIX = 1

	local self = Animation.CurveTimeline.new()
	self.frames = {} -- time, mix, bendDirection, ...
	self.ikConstraintIndex = -1

	function self:getDuration ()
		return self.frames[#self.frames - 2]
	end

	function self:getFrameCount ()
		return (#self.frames + 1) / 3
	end

	function self:setFrame (frameIndex, time, mix, bendDirection)
		frameIndex = frameIndex * 3
		self.frames[frameIndex] = time
		self.frames[frameIndex + 1] = mix
		self.frames[frameIndex + 2] = bendDirection
	end

	function self:apply (skeleton, lastTime, time, firedEvents, alpha)
		local frames = self.frames
		if time < frames[0] then return end -- Time is before first frame.

		local ikConstraint = skeleton.ikConstraints[self.ikConstraintIndex]

		if time >= frames[#frames - 2] then -- Time is after last frame.
			ikConstraint.mix = ikConstraint.mix + (frames[#frames - 1] - ikConstraint.mix) * alpha
			ikConstraint.bendDirection = frames[#frames]
			return
		end

		-- Interpolate between the previous frame and the current frame.
		local frameIndex = binarySearch(frames, time, 3);
		local prevFrameMix = frames[frameIndex + PREV_FRAME_MIX]
		local frameTime = frames[frameIndex]
		local percent = 1 - (time - frameTime) / (frames[frameIndex + PREV_FRAME_TIME] - frameTime)
		if percent < 0 then percent = 0 elseif percent > 1 then percent = 1 end
		percent = self:getCurvePercent(frameIndex / 3 - 1, percent)

		local mix = prevFrameMix + (frames[frameIndex + FRAME_MIX] - prevFrameMix) * percent
		ikConstraint.mix = ikConstraint.mix + (mix - ikConstraint.mix) * alpha
		ikConstraint.bendDirection = frames[frameIndex + PREV_FRAME_BEND_DIRECTION]
	end

	return self
end

return Animation
