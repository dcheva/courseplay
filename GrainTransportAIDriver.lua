--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class GrainTransportAIDriver : AIDriver
GrainTransportAIDriver = CpObject(AIDriver)

--- Constructor
function GrainTransportAIDriver:init(vehicle)
	courseplay.debugVehicle(11,vehicle,'GrainTransportAIDriver:init()')
	AIDriver.init(self, vehicle)
	self.mode = courseplay.MODE_GRAIN_TRANSPORT
	-- just for backwards compatibility
end

function GrainTransportAIDriver:setHudContent()
	AIDriver.setHudContent(self)
	courseplay.hud:setGrainTransportAIDriverContent(self.vehicle)
end

function GrainTransportAIDriver:start(startingPoint)
	self.vehicle:setCruiseControlMaxSpeed(self.vehicle:getSpeedLimit() or math.huge)
	AIDriver.start(self, startingPoint)
	self:setDriveUnloadNow(false);
	self.vehicle.cp.siloSelectedFillType = FillType.UNKNOWN
end

function GrainTransportAIDriver:isAlignmentCourseNeeded(ix)
	-- never use alignment course for grain transport mode
	return false
end

--TODO: consolidate this with AIDriver:drive() 
function GrainTransportAIDriver:drive(dt)
	-- make sure we apply the unload offset when needed
	self:updateOffset()
	-- update current waypoint/goal point
	self.ppc:update()

	-- RESET TRIGGER RAYCASTS from drive.lua.
	-- TODO: Not sure how raycast can be called twice if everything is coded cleanly.
	self.vehicle.cp.hasRunRaycastThisLoop['tipTrigger'] = false
	self.vehicle.cp.hasRunRaycastThisLoop['specialTrigger'] = false

	courseplay:updateFillLevelsAndCapacities(self.vehicle)

	-- should we give up control so some other code can drive?
	local giveUpControl = false
	-- should we keep driving?
	local allowedToDrive = self:checkLastWaypoint()
	
	if self:getSiloSelectedFillTypeSetting():isEmpty() then 
		allowedToDrive = false
		self:setInfoText('NO_SELECTED_FILLTYPE')
	else
		self:clearInfoText('NO_SELECTED_FILLTYPE')
		
		if self:isNearFillPoint() then
			self.triggerHandler:enableFillTypeLoading()
			self.triggerHandler:disableFillTypeUnloading()
		else 
			self.triggerHandler:enableFillTypeUnloading()
			self.triggerHandler:disableFillTypeLoading()
		end
			-- TODO: are these checks really necessary?
		if self.vehicle.cp.totalFillLevel ~= nil
			and self.vehicle.cp.tipRefOffset ~= nil
			and self.vehicle.cp.workToolAttached then

			self:searchForTipTriggers()
			allowedToDrive, giveUpControl = self:onUnLoadCourse(allowedToDrive, dt)
		else
			self:debug('Safety check failed')
		end
	end
	
	-- TODO: clean up the self.allowedToDrives above and use a local copy
	if self.state == self.states.STOPPED or not allowedToDrive or self.triggerHandler:isLoading() or self.triggerHandler:isUnloading() then
		self:hold()
	end
	self:updateInfoText()

	if giveUpControl then
		-- unload_tippers does the driving
		return
	else
		-- collision detection
		self:detectCollision(dt)
		-- we drive the course as usual
		self:driveCourse(dt)
	end
end

--can be removed maybe ??
function GrainTransportAIDriver:onWaypointChange(newIx)
	self:debug('On waypoint change %d', newIx)
	AIDriver.onWaypointChange(self, newIx)
	if self.course:isLastWaypointIx(newIx) then
		self:debug('Reaching last waypoint')
		self:setDriveUnloadNow(false);
	end
end

--this one is probably broken ??
-- TODO: move this into onWaypointPassed() instead
function GrainTransportAIDriver:checkLastWaypoint()
	local allowedToDrive = true
	if self.ppc:getCurrentWaypointIx() == self.course:getNumberOfWaypoints() then
	--	courseplay:openCloseCover(self.vehicle, not courseplay.SHOW_COVERS)
		if not self:getSiloSelectedFillTypeSetting():isActive() then
			-- stop at the last waypoint when the run counter expires
			allowedToDrive = false
			self:stop('END_POINT_MODE_1')
			self:debug('Last run (%d) finished, stopping.', self.runCounter)
		else
			-- continue at the first waypoint
			self.ppc:initialize(1)
			self:debug('Finished run %d, continue with next.', self.runCounter)
		end
	end
	return allowedToDrive
end

function GrainTransportAIDriver:updateLights()
	self.vehicle:setBeaconLightsVisibility(false)
end

--function GrainTransportAIDriver:getCanShowDriveOnButton()
--	return self:isNearFillPoint()
--end

function GrainTransportAIDriver:getSiloSelectedFillTypeSetting()
	return self.vehicle.cp.settings.siloSelectedFillTypeGrainTransportDriver
end

function GrainTransportAIDriver:getSeperateFillTypeLoadingSetting()
	return self.vehicle.cp.settings.seperateFillTypeLoading
end

