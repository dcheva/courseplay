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
	self.waitAtOverloadingPoint = false
	self.ignoreLoadingTrigger = false
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
--	self.ppc:update()

	-- RESET TRIGGER RAYCASTS from drive.lua.
	-- TODO: Not sure how raycast can be called twice if everything is coded cleanly.
	self.vehicle.cp.hasRunRaycastThisLoop['tipTrigger'] = false
	self.vehicle.cp.hasRunRaycastThisLoop['specialTrigger'] = false

	courseplay:updateFillLevelsAndCapacities(self.vehicle)

	-- should we give up control so some other code can drive?
	local giveUpControl = false
	-- should we keep driving?
--	local allowedToDrive = self:checkLastWaypoint()
	local allowedToDrive = true
	if self:getSiloSelectedFillTypeSetting():isEmpty() then 
		courseplay:setInfoText(self.vehicle, "COURSEPLAY_MANUAL_LOADING")
		self.ignoreLoadingTrigger = true
	end
--		allowedToDrive = false
--		self:setInfoText('NO_SELECTED_FILLTYPE')
--		self.ignoreLoadingTrigger = true
--	else
--		self:clearInfoText('NO_SELECTED_FILLTYPE')
		
	if self:isNearFillPoint() then
		if not self:getSiloSelectedFillTypeSetting():isEmpty() then
			self.triggerHandler:enableFillTypeLoading()
			
		end
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
--	end
	
	-- TODO: clean up the self.allowedToDrives above and use a local copy
	if not allowedToDrive then
		self:hold()
	end
	
	if self.waitAtOverloadingPoint then 
		courseplay:setInfoText(self.vehicle, "COURSEPLAY_MANUAL_LOADING")
		self:setInfoText('REACHED_OVERLOADING_POINT')
		self:checkFillUnits()
		self:continue()
		self:hold()
	else
		self:clearInfoText('REACHED_OVERLOADING_POINT')
	end	

	
	if giveUpControl then
		self.ppc:update()
		-- unload_tippers does the driving
		return
	else
		-- collision detection
	--	self:detectCollision(dt)
		-- we drive the course as usual
		AIDriver.drive(self,dt)
	end
end

function GrainTransportAIDriver:onWaypointPassed(ix)
	--firstWaypoint/ start
	if ix == 1 then 
		if not self.triggerHandler:isInTrigger() then 
			self.waitAtOverloadingPoint = true
			local totalFillUnitsData = {}
			self.totalFillCapacity = 0
			self.totalFillLevel = 0
			self:getFillUnitInfo(self.vehicle,totalFillUnitsData)
			for object, objectData in pairs(totalFillUnitsData) do 
				for fillUnitIndex, fillUnitData in pairs(objectData) do 
					SpecializationUtil.raiseEvent(object, "onAddedFillUnitTrigger",fillUnitData.fillType,fillUnitIndex,1)
					self.totalFillCapacity = self.totalFillCapacity + fillUnitData.capacity
					self.totalFillLevel = self.totalFillLevel + fillUnitData.fillLevel
				end
			end
			return
		end
	end
	if not self.waitAtOverloadingPoint then 
		AIDriver.onWaypointPassed(self,ix)
	end
end

-- --this one is probably broken ??
-- -- TODO: move this into onWaypointPassed() instead
-- function GrainTransportAIDriver:checkLastWaypoint()
	-- local allowedToDrive = true
	-- if self.ppc:getCurrentWaypointIx() == self.course:getNumberOfWaypoints() then
		-- if self:getSiloSelectedFillTypeSetting():isEmpty() then 
			-- courseplay:openCloseCover(self.vehicle, not courseplay.SHOW_COVERS)
			-- if self:areFillUnitsNotFull() then 
				-- return
			-- end
		-- end
	-- --	if not self:getSiloSelectedFillTypeSetting():isActive() then
			-- -- stop at the last waypoint when the run counter expires
	-- --		allowedToDrive = false
	-- --		self:stop('END_POINT_MODE_1')
	-- --		self:debug('Last run (%d) finished, stopping.', self.runCounter)
	-- --	else
			-- -- continue at the first waypoint
			-- self.ppc:initialize(1)
			-- self:debug('Finished run , continue with next.')
	-- --	end
	-- end
	-- return allowedToDrive
-- end

function GrainTransportAIDriver:updateLights()
	self.vehicle:setBeaconLightsVisibility(false)
end

function GrainTransportAIDriver:getSiloSelectedFillTypeSetting()
	return self.vehicle.cp.settings.siloSelectedFillTypeGrainTransportDriver
end

function GrainTransportAIDriver:getSeperateFillTypeLoadingSetting()
	return self.vehicle.cp.settings.seperateFillTypeLoading
end

function GrainTransportAIDriver:checkFillUnits()
	local totalFillTypeData = {}
	local fillLevelOkay = true
	local totalFillCapacity = 0
	local totalFillLevel = 0
	self:getFillTypeInfo(self.vehicle,totalFillTypeData)
	local maxNeeded = self.vehicle.cp.settings.driveOnAtFillLevel:get()
	local fillTypeTotalData,fillTypeDataSize = self.triggerHandler:getSiloSelectedFillTypeData()
	for fillTypeIndex,data in pairs(totalFillTypeData) do 
	--	print(string.format("fillTypeIndex: %s, fillLevelPercentage: %s, capacity: %s, fillLevel: %s",tostring(fillTypeIndex),tostring(data.fillLevelPercentage),tostring(data.capacity),tostring(data.fillLevel)))
		totalFillCapacity = totalFillCapacity+data.capacity
		totalFillLevel = totalFillLevel + data.fillLevel
		if self:getSeperateFillTypeLoadingSetting():isActive() and fillTypeDataSize>0 then
			local fillTypeMaxFound 
			for _,fillTypeData in ipairs(fillTypeTotalData) do 
				if fillTypeIndex == fillTypeData.fillType then 
					if data.fillLevelPercentage< fillTypeData.maxFillLevel then 
						fillLevelOkay = false
						break
					end
					fillTypeMaxFound =fillTypeData.maxFillLevel
				end
			end 
			print(string.format("fillLevelPercentage: %s, maxFillLevelFound: %s, maxNeeded: %s",tostring(data.fillLevelPercentage),tostring(fillTypeMaxFound~=nil),tostring(fillTypeMaxFound or 99)))
			if not fillTypeMaxFound then 
				if data.fillLevelPercentage<99 then 
					fillLevelOkay = false
				end
			end
			if not fillLevelOkay then 
				break
			end
		end
	end
	if not self:getSeperateFillTypeLoadingSetting():isActive() then
		print(string.format("totalFillCapacity: %s, totalFillLevel: %s, maxNeeded: %s, diff: %s",tostring(self.totalFillCapacity),tostring(self.totalFillLevel),tostring(maxNeeded),tostring(self.totalFillLevel/self.totalFillCapacity*100)))
		if (self.totalFillLevel/self.totalFillCapacity)*100 < maxNeeded then 
			fillLevelOkay = false
		end
	else 
		if totalFillCapacity ~= self.totalFillCapacity then 
			fillLevelOkay = false
		end
	end

	if fillLevelOkay then 
		self.waitAtOverloadingPoint = false
		local totalFillUnitsData = {}
		self:getFillUnitInfo(self.vehicle,totalFillUnitsData)
		for object, objectData in pairs(totalFillUnitsData) do 
			SpecializationUtil.raiseEvent(object, "onRemovedFillUnitTrigger",0)
		end
	end
end

function GrainTransportAIDriver:getFillUnitInfo(object,totalFillUnitsData)
	local spec = object.spec_fillUnit
	if spec and object.spec_trailer then 
		totalFillUnitsData[object] = {}
		for fillUnitIndex,fillUnit in pairs(object:getFillUnits()) do 
			totalFillUnitsData[object][fillUnitIndex] = {}
			local fillLevelPercentage = object:getFillUnitFillLevelPercentage(fillUnitIndex)*100
			local capacity = object:getFillUnitCapacity(fillUnitIndex)
			local fillLevel = object:getFillUnitFillLevel(fillUnitIndex)
			local fillType = object:getFillUnitFillType(fillUnitIndex)
			totalFillUnitsData[object][fillUnitIndex].fillLevelPercentage = fillPercentage
			totalFillUnitsData[object][fillUnitIndex].capacity = capacity
			totalFillUnitsData[object][fillUnitIndex].fillLevel = fillLevel
			totalFillUnitsData[object][fillUnitIndex].fillType = fillType
		end
	end
	-- get all attached implements recursively
	for _,impl in pairs(object:getAttachedImplements()) do
		self:getFillUnitInfo(impl.object,totalFillUnitsData)
	end
end

function GrainTransportAIDriver:getFillTypeInfo(object,totalFillTypeData)
	local spec = object.spec_fillUnit
	if spec and object.spec_trailer then 
		for fillUnitIndex,fillUnit in pairs(object:getFillUnits()) do 
			local fillLevelPercentage = object:getFillUnitFillLevelPercentage(fillUnitIndex)*100
			local capacity = object:getFillUnitCapacity(fillUnitIndex)
			local fillLevel = object:getFillUnitFillLevel(fillUnitIndex)
			local fillType = object:getFillUnitFillType(fillUnitIndex)
			if fillType then
				if totalFillTypeData[fillType] == nil then 
					totalFillTypeData[fillType] = {}
					totalFillTypeData[fillType].capacity = capacity
					totalFillTypeData[fillType].fillLevel = fillLevel
					totalFillTypeData[fillType].fillLevelPercentage = fillLevelPercentage
				else
					totalFillTypeData[fillType].capacity = totalFillTypeData[fillType].capacity +capacity
					totalFillTypeData[fillType].fillLevel = totalFillTypeData[fillType].fillLevel + fillLevel
					totalFillTypeData[fillType].fillLevelPercentage = totalFillTypeData[fillType].fillLevel/totalFillTypeData[fillType].capacity*100
				end
			end
		end
	end
	-- get all attached implements recursively
	for _,impl in pairs(object:getAttachedImplements()) do
		self:getFillTypeInfo(impl.object,totalFillTypeData)
	end
end