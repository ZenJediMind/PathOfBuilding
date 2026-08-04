-- Path of Building
--
-- Class: Mercenary Tab
-- Permanent Mercenary configuration, persistence, and equipment validation.
--
local MercenaryTools = require("Modules/MercenaryTools")
local skillOptions = require("Modules/SkillOptions")
local gemTooltip = LoadModule("Classes/GemTooltip")

local t_insert = table.insert
local t_sort = table.sort
local m_floor = math.floor
local m_min = math.min
local m_max = math.max

local function gemColorLabel(color)
	if not color then return "" end
	return (data.skillColorMap[color] or colorCodes.NORMAL)
end

local function supportLabel(support)
	return gemColorLabel(support and support.color)..(support and support.name or "?").." (Tier "..(support and support.variant or "?")..")"
end

local function mercenaryLevel(build, foundAreaLevel)
	local currentAreaLevel = build.configTab and build.configTab.enemyLevel
	return MercenaryTools.effectiveLevel(foundAreaLevel, currentAreaLevel)
end

local SUPPORTED_SLOTS = { }
for _, slotName in ipairs(MercenaryTools.equipmentSlots) do SUPPORTED_SLOTS[slotName] = true end
local ARMOUR_SLOTS = {
	Helmet = true,
	["Body Armour"] = true,
	Gloves = true,
	Boots = true,
}
-- Unique equipment is only permitted where something has granted the matching
-- "Your Mercenary can equip Unique ..." flag. Body Armour has no such flag.
local UNIQUE_FLAG_BY_SLOT = {
	["Weapon 1"] = "MercenaryCanEquipUniqueArms",
	["Weapon 2"] = "MercenaryCanEquipUniqueArms",
	Helmet = "MercenaryCanEquipUniqueHelmets",
	Gloves = "MercenaryCanEquipUniqueGloves",
	Boots = "MercenaryCanEquipUniqueBoots",
	Amulet = "MercenaryCanEquipUniqueAmulets",
	["Ring 1"] = "MercenaryCanEquipUniqueRings",
	["Ring 2"] = "MercenaryCanEquipUniqueRings",
	Belt = "MercenaryCanEquipUniqueBelts",
}
local UNIQUE_SLOT_DESCRIPTION = {
	MercenaryCanEquipUniqueArms = "Unique Weapons, Shields and Quivers",
	MercenaryCanEquipUniqueHelmets = "Unique Helmets",
	MercenaryCanEquipUniqueGloves = "Unique Gloves",
	MercenaryCanEquipUniqueBoots = "Unique Boots",
	MercenaryCanEquipUniqueAmulets = "Unique Amulets",
	MercenaryCanEquipUniqueRings = "Unique Rings",
	MercenaryCanEquipUniqueBelts = "Unique Belts",
}

local MercenarySkillListClass = newClass("MercenarySkillListControl", "ListControl", function(self, anchor, rect, mercenaryTab)
	self.ListControl(anchor, rect, 16, "VERTICAL", true, mercenaryTab.profile.skills)
	self.mercenaryTab = mercenaryTab
	self.label = "^7Skill Groups:"
	self.controls.delete = new("ButtonControl", { "BOTTOMRIGHT", self, "TOPRIGHT" }, { 0, -2, 60, 18 }, "Delete", function()
		self:OnSelDelete(self.selIndex)
	end)
	self.controls.delete.enabled = function()
		return self.selValue ~= nil
	end
	self.controls.new = new("ButtonControl", { "RIGHT", self.controls.delete, "LEFT" }, { -4, 0, 60, 18 }, "New", function()
		mercenaryTab:AddSkill()
	end)
	self.controls.new.enabled = function()
		return mercenaryTab.skillOptions and #mercenaryTab.skillOptions > 1
	end
end)

function MercenarySkillListClass:GetRowValue(_, _, skill)
	local skillData = self.mercenaryTab.data.skills[skill.id]
	local skillEffect = self.mercenaryTab.build.data.skills[skill.id]
	local label = gemColorLabel(skillEffect and skillEffect.color)..(skillData and skillData.name or skill.id or "?")
	if skill.enabled == false then label = colorCodes.NEGATIVE..label.." (Disabled)" end
	if skill.includeInFullDPS then label = label..colorCodes.CUSTOM.." (FullDPS)" end
	if #(skill.supports or { }) > 0 then label = label.." ^7+ "..#skill.supports.." support"..(#skill.supports == 1 and "" or "s") end
	return label
end

function MercenarySkillListClass:OnHoverKeyUp(key)
	local skill = self.ListControl:GetHoverValue()
	if not skill then return end
	local skillData = self.mercenaryTab.data.skills[skill.id]
	if itemLib.wiki.matchesKey(key) then
		if skillData then itemLib.wiki.openGem(skillData.name) end
	elseif key == "RIGHTBUTTON" and IsKeyDown("CTRL") then
		skill.includeInFullDPS = not skill.includeInFullDPS
		self.mercenaryTab:Changed()
	elseif key == "LEFTBUTTON" and IsKeyDown("CTRL") then
		skill.enabled = skill.enabled == false
		self.mercenaryTab:Changed()
	end
end

function MercenarySkillListClass:OnSelect(index)
	self.mercenaryTab.selectedSkillIndex = index
	self.mercenaryTab:RefreshControls()
end

function MercenarySkillListClass:AddValueTooltip(tooltip, _, skill)
	local tab = self.mercenaryTab
	if tooltip:CheckForUpdate(skill, tab.build.outputRevision, mercenaryLevel(tab.build, tab.profile.foundAreaLevel)) then
		tooltip:Clear()
		tab:AddSkillTooltip(tooltip, skill, false)
	end
end

function MercenarySkillListClass:OnSelDelete(index)
	if index then self.mercenaryTab:SetSkill(index, nil) end
end

function MercenarySkillListClass:OnOrderChange(_, newIndex)
	self.mercenaryTab.selectedSkillIndex = newIndex
	self.mercenaryTab:Changed()
end

local MercenaryTabClass = newClass("MercenaryTab", "ControlHost", "Control", function(self, build)
	self.ControlHost()
	self.Control()
	self.build = build
	self.data = build.data.mercenaries
	self.classGroups, self.classGroupsByClassId = MercenaryTools.classGroups(self.data)
	self.mercenarySets = { }
	self.mercenarySetOrderList = { 1 }
	self:NewMercenarySet(1)
	self.activeMercenarySetId = 1
	self.profile = self.mercenarySets[1]
	self.sortGemsByDPS = true
	self.sortGemsByDPSField = "CombinedDPS"
	self.supportSortRevision = 0
	self.supportSortCache = { }
	self.supportSortCoroutine = nil
	self.supportSortStatus = ""
	self.selectedSkillIndex = 1
	self.errors = { }

	self.controls.classLabel = new("LabelControl", { "TOPLEFT", self, "TOPLEFT" }, { 12, 12, 0, 16 }, "^7Mercenary class:")
	self.controls.class = new("DropDownControl", { "LEFT", self.controls.classLabel, "RIGHT" }, { 8, 0, 240, 20 }, { }, function(_, value)
		local classGroup = value
		self.profile.classId = classGroup and classGroup.classIds[1]
		self.profile.buildId = nil
		self.profile.skills = { }
		self.profile.mainSkillId = nil
		self.selectedSkillIndex = 1
		self:Changed()
	end)
	self.controls.class:SetList(self.classGroups)
	self.controls.setLabel = new("LabelControl", { "LEFT", self.controls.class, "RIGHT" }, { 20, 0, 0, 16 }, "^7Mercenary set:")
	self.controls.setSelect = new("DropDownControl", { "LEFT", self.controls.setLabel, "RIGHT" }, { 8, 0, 210, 20 }, { }, function(_, value)
		if value then self:SetActiveMercenarySet(value.id) end
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.mercenarySetOrderList > 1
	end
	self.controls.setManage = new("ButtonControl", { "LEFT", self.controls.setSelect, "RIGHT" }, { 4, 0, 90, 20 }, "Manage...", function()
		self:OpenMercenarySetManagePopup()
	end)
	self.controls.buildLabel = new("LabelControl", { "TOPLEFT", self.controls.classLabel, "BOTTOMLEFT" }, { 0, 12, 0, 16 }, "^7Class and build:")
	self.controls.build = new("DropDownControl", { "LEFT", self.controls.buildLabel, "RIGHT" }, { 8, 0, 300, 20 }, { }, function(_, value)
		self.profile.buildId = value and value.id
		self.profile.classId = value and value.classId or self.profile.classId
		self.profile.skills = { }
		self.profile.mainSkillId = nil
		self.selectedSkillIndex = 1
		self:Changed()
	end)
	self.controls.levelLabel = new("LabelControl", { "LEFT", self.controls.build, "RIGHT" }, { 20, 0, 0, 16 }, "^7Found-area level:")
	self.controls.level = new("EditControl", { "LEFT", self.controls.levelLabel, "RIGHT" }, { 6, 0, 55, 20 }, "68", nil, "%D", 3, function(buf)
		self.profile.foundAreaLevel = m_min(m_max(tonumber(buf) or 1, 1), 100)
		self:Changed()
	end)

	self.controls.editEquipment = new("ButtonControl", { "TOPLEFT", self.controls.buildLabel, "BOTTOMLEFT" }, { 0, 14, 150, 20 }, "Edit Equipment", function()
		build.viewMode = "ITEMS"
	end)
	self.controls.reset = new("ButtonControl", { "LEFT", self.controls.editEquipment, "RIGHT" }, { 8, 0, 80, 20 }, "Reset", function()
		self:Reset()
	end)
	self.controls.lifeComparisonLabel = new("LabelControl", { "LEFT", self.controls.reset, "RIGHT" }, { 20, 0, 0, 16 }, "^7Loyal Bodyguard:")
	self.controls.lifeComparison = new("DropDownControl", { "LEFT", self.controls.lifeComparisonLabel, "RIGHT" }, { 6, 0, 170, 20 }, {
		{ label = "Automatic Life comparison", id = "AUTO" },
		{ label = "Mercenary has higher Life", id = "MERCENARY" },
		{ label = "Player has higher Life", id = "PLAYER" },
	}, function(_, value)
		self.profile.lifeComparison = value.id
		self:Changed()
	end)

	self.controls.skillList = new("MercenarySkillListControl", { "TOPLEFT", self.controls.editEquipment, "BOTTOMLEFT" }, { 0, 38, 360, 300 }, self)
	self.controls.skillTip = new("LabelControl", { "TOPLEFT", self.controls.skillList, "BOTTOMLEFT" }, { 0, 8, 0, 14 }, [[
^7Usage Tips:
- Ctrl + Click to enable/disable skill groups.
- Ctrl + Right click to include/exclude in Full DPS calculations.
]])
	self.controls.optionSection = new("SectionControl", { "TOPLEFT", self.controls.skillList, "BOTTOMLEFT" }, { 0, 60, 360, 70 }, "Gem Options")
	self.controls.sortGemsByDPS = new("CheckBoxControl", { "TOPLEFT", self.controls.optionSection, "TOPLEFT" }, { 170, 20, 20 }, "Sort gems by DPS:", function(state)
		self.sortGemsByDPS = state
		self:InvalidateSupportSort()
		self:RefreshSupportLists()
	end, nil, true)
	self.controls.sortGemsByDPSFieldControl = new("DropDownControl", { "LEFT", self.controls.sortGemsByDPS, "RIGHT" }, { 10, 0, 140, 20 }, skillOptions.sortGemTypeList, function(_, value)
		self.sortGemsByDPSField = value.type
		self:InvalidateSupportSort()
		self:RefreshSupportLists()
	end)
	self.controls.sortGemsByDPSFieldControl:SelByValue(self.sortGemsByDPSField, "type")
	self.controls.skillDetailAnchor = new("Control", { "TOPLEFT", self.controls.skillList, "TOPRIGHT" }, { 20, 0, 0, 0 })
	self.controls.skillDetailAnchor.shown = function()
		return self.profile.skills[self.selectedSkillIndex] ~= nil
	end
	self.controls.skillLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 0, 2, 0, 16 }, "^7Skill:")
	self.controls.skill = new("DropDownControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 85, 0, 380, 20 }, { }, function(_, value)
		self:SetSkill(self.selectedSkillIndex, value and value.id)
	end)
	self.controls.skill.tooltipFunc = function(tooltip, mode, index, value)
		if tooltip:CheckForUpdate(mode, index, value, self.build.outputRevision, mercenaryLevel(self.build, self.profile.foundAreaLevel), self.selectedSkillIndex) then
			tooltip:Clear()
			if value and value.id then
				self:AddSkillTooltip(tooltip, value, mode == "HOVER")
			end
		end
	end
	self.controls.skillEnabledLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 0, 32, 0, 16 }, "^7Enabled:")
	self.controls.skillEnabled = new("CheckBoxControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 68, 30, 20 }, nil, function(state)
		local skill = self.profile.skills[self.selectedSkillIndex]
		if skill then skill.enabled = state end
		self:Changed()
	end)
	self.controls.skillFullDPSLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 108, 32, 0, 16 }, "^7Include in Full DPS:")
	self.controls.skillFullDPS = new("CheckBoxControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 247, 30, 20 }, nil, function(state)
		local skill = self.profile.skills[self.selectedSkillIndex]
		if skill then skill.includeInFullDPS = state end
		self:Changed()
	end)
	self.controls.skillCountLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 287, 32, 0, 16 }, "^7Count:")
	self.controls.skillCount = new("EditControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 335, 30, 50, 20 }, "1", nil, "%D", 2, function(buf)
		local skill = self.profile.skills[self.selectedSkillIndex]
		if skill then skill.count = m_min(m_max(tonumber(buf) or 1, 1), 99) end
		self:Changed()
	end)
	self.controls.skillPartLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 0, 64, 0, 16 }, "^7Skill part:")
	self.controls.skillPart = new("DropDownControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 85, 62, 180, 20 }, { }, function(_, value)
		local selected = self.profile.skills[self.selectedSkillIndex]
		if selected and value then selected.skillPart = value.index end
		self:Changed()
	end)
	self.controls.skillMinionSkillLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 285, 64, 0, 16 }, "^7Minion skill:")
	self.controls.skillMinionSkill = new("DropDownControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 375, 62, 230, 20 }, { }, function(_, value)
		local selected = self.profile.skills[self.selectedSkillIndex]
		if selected and value then selected.skillMinionSkill = value.index end
		self:Changed()
	end)

	self.controls.supportsHeader = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 0, 102, 0, 16 }, function()
		local skill = self.profile.skills[self.selectedSkillIndex]
		return "^7Supports for "..(skill and self.data.skills[skill.id] and self.data.skills[skill.id].name or "selected skill")..":"
	end)
	self.controls.supportSortStatus = new("LabelControl", { "LEFT", self.controls.supportsHeader, "RIGHT" }, { 8, 0, 0, 16 }, function()
		return self.supportSortCoroutine and "^7Sorting "..self.supportSortStatus or ""
	end)
	self.supportControls = { }
	local function createSupportRow(index)
		local y = 124 + (index - 1) * 22
		local clear = new("ButtonControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 0, y, 20, 20 }, "x", function()
			self:SetSupport(index, nil)
		end)
		clear.enabled = function()
			local skill = self.profile.skills[self.selectedSkillIndex]
			return skill and skill.supports[index] ~= nil
		end
		local control = new("DropDownControl", { "LEFT", clear, "RIGHT" }, { 2, 0, 380, 20 }, { }, function(_, value)
			self:SetSupport(index, value and value.id)
		end)
		control.tooltipFunc = function(tooltip, mode, _, value)
			if tooltip:CheckForUpdate(mode, value, self.build.outputRevision, self.supportSortRevision, mercenaryLevel(self.build, self.profile.foundAreaLevel), self.selectedSkillIndex) then
				tooltip:Clear()
				local support = value and value.id and self.data.supports[value.id]
				self:AddSupportTooltip(tooltip, support, index, mode == "HOVER")
			end
		end
		local onKeyDown = control.OnKeyDown
		control.OnKeyDown = function(dropdown, key)
			if not dropdown.dropped and (key == "LEFTBUTTON" or key == "RIGHTBUTTON" or key == "DOWN") then
				self:QueueSupportSort(index)
			end
			return onKeyDown(dropdown, key)
		end
		control.supportIndex = index
		self.controls["support"..index.."Clear"] = clear
		self.controls["support"..index] = control
		return control
	end
	for index = 1, MercenaryTools.maxSupportLimit(self.data) do
		self.supportControls[index] = createSupportRow(index)
	end

	self.controls.errorsHeader = new("LabelControl", { "TOPLEFT", self.controls.optionSection, "BOTTOMLEFT" }, { 0, 12, 0, 16 }, "^7Warnings (informational):")
	self.controls.errors = new("TextListControl", { "TOPLEFT", self.controls.errorsHeader, "BOTTOMLEFT" }, { 0, 4, 760, 110 }, { { x = 4, align = "LEFT" } }, self.errors)
	self:RefreshControls()
end)

local function makeMercenarySkillGem(build, skillData, actorLevel)
	local grantedEffect = build.data.skills[skillData.id]
	if not grantedEffect or not grantedEffect.levels then return end
	local sourceGem = build.data.gemForSkill and build.data.gems[build.data.gemForSkill[grantedEffect]]
	local effect = copyTable(grantedEffect, true)
	effect.name = skillData.name or effect.name
	effect.description = skillData.description or effect.description
	if skillData.icon and skillData.icon ~= "" then effect.icon = skillData.icon end
	effect.stats = effect.stats or { }
	effect.constantStats = effect.constantStats or { }
	local secondary = skillData.secondarySkillId and build.data.skills[skillData.secondarySkillId]
	if secondary then
		secondary = copyTable(secondary, true)
	end
	local level = MercenaryTools.skillLevel(effect, actorLevel)
	return {
		level = level,
		actorLevel = actorLevel,
		color = data.skillColorMap[effect.color] or colorCodes.NORMAL,
		quality = 0,
		gemData = {
			name = effect.name,
			grantedEffect = effect,
			secondaryGrantedEffect = secondary,
			tags = sourceGem and copyTable(sourceGem.tags or { }, true) or { },
			tagString = sourceGem and sourceGem.tagString or "Mercenary Skill",
			naturalMaxLevel = #effect.levels,
			reqStr = 0,
			reqDex = 0,
			reqInt = 0,
		},
	}
end

local function makeMercenarySupportGem(build, support)
	if not support then return end
	local templateId = build.data.mercenaryStatData.supportTemplates[support.id]
	local template = templateId and build.data.skills[templateId]
	local effect = {
		name = support.name,
		icon = support.icon,
		support = true,
		statDescriptionScope = template and template.statDescriptionScope or "gem_stat_descriptions",
		stats = { },
		constantStats = { },
		levels = { { levelRequirement = 1 } },
		statMap = build.data.mercenarySupportStatMap,
	}
	for _, stat in ipairs(support.stats or { }) do
		t_insert(effect.constantStats, { stat.id, stat.value })
	end
	return {
		level = 1,
		quality = 0,
		gemData = {
			name = support.name,
			grantedEffect = effect,
			tags = { },
			tagString = "Mercenary Support, Tier "..tostring(support.variant),
			naturalMaxLevel = 1,
			reqStr = 0,
			reqDex = 0,
			reqInt = 0,
		},
	}
end

local function addMercenaryComparison(tab, tooltip, preview, header)
	if not preview then return end
	local calcTab = tab.build.calcsTab
	local calcFunc, _, baseOutputs = calcTab and calcTab.GetMiscCalculator and calcTab:GetMiscCalculator()
	local baseOutput = baseOutputs and baseOutputs.MERCENARY
	if not calcFunc or not baseOutput or not calcTab.mainEnv then return end
	local ok, output = pcall(calcFunc, { comparisonActor = "MERCENARY" }, tab.sortGemsByDPSField == "FullDPS")
	if ok and output then
		tab.build:AddStatComparesToTooltip(tooltip, baseOutput, output, header, nil, "MERCENARY")
	else
		tooltip:AddLine(16, colorCodes.WARNING.."Mercenary comparison unavailable")
	end
end

function MercenaryTabClass:AddSkillTooltip(tooltip, value, preview)
	local skillData = value and self.data.skills[value.id]
	local actorLevel = mercenaryLevel(self.build, self.profile.foundAreaLevel)
	local gemInstance = skillData and makeMercenarySkillGem(self.build, skillData, actorLevel)
	if not gemInstance then
		tooltip:AddLine(16, colorCodes.WARNING.."No exported Mercenary skill data")
		return
	end
	gemTooltip.AddGemTooltip(tooltip, self.build, gemInstance, { skipRequirements = true })
	if preview then
		local selected = self.profile.skills[self.selectedSkillIndex]
		if selected then
			local oldId, oldSupports = selected.id, selected.supports
			local oldEnabled, oldFullDPS, oldCount = selected.enabled, selected.includeInFullDPS, selected.count
			local oldSkillPart, oldStageCount = selected.skillPart, selected.skillStageCount
			local oldMineCount, oldMinionSkill = selected.skillMineCount, selected.skillMinionSkill
			local oldMainSkillId = self.profile.mainSkillId
			selected.id = value.id
			selected.supports = { }
			selected.enabled = true
			selected.includeInFullDPS = false
			selected.count = 1
			selected.skillPart = self.build.data.mercenaryStatData.defaultSkillParts[value.id] or 1
			selected.skillStageCount = nil
			selected.skillMineCount = nil
			selected.skillMinionSkill = nil
			self.profile.mainSkillId = value.id
			addMercenaryComparison(self, tooltip, true, "^7Selecting this skill will give you:")
			selected.id, selected.supports = oldId, oldSupports
			selected.enabled, selected.includeInFullDPS, selected.count = oldEnabled, oldFullDPS, oldCount
			selected.skillPart, selected.skillStageCount = oldSkillPart, oldStageCount
			selected.skillMineCount, selected.skillMinionSkill = oldMineCount, oldMinionSkill
			self.profile.mainSkillId = oldMainSkillId
		end
	end
end

function MercenaryTabClass:AddSupportTooltip(tooltip, support, index, preview)
	local gemInstance = support and makeMercenarySupportGem(self.build, support)
	if not gemInstance then
		if index then tooltip:AddLine(16, "^7Remove this support") end
		return
	end
	gemTooltip.AddGemTooltip(tooltip, self.build, gemInstance, { skipRequirements = true })
	if preview then
		local selected = self.profile.skills[self.selectedSkillIndex]
		local selectedData = selected and self.data.skills[selected.id]
		if selected and selectedData and selectedData.possibleSupportIds then
			local supportIndex = m_min(index, #selected.supports + 1)
			local oldSupport = selected.supports[supportIndex]
			selected.supports[supportIndex] = { id = support.id, tier = support.variant }
			addMercenaryComparison(self, tooltip, true, "^7Selecting this support will give you:")
			selected.supports[supportIndex] = oldSupport
		end
	end
end

function MercenaryTabClass:Changed()
	self.modFlag = true
	self.build.buildFlag = true
	self:InvalidateSupportSort()
	self:RefreshControls()
end

function MercenaryTabClass:InvalidateSupportSort()
	self.supportSortRevision = self.supportSortRevision + 1
	self.supportSortCache = { }
	self.supportSortCoroutine = nil
	self.supportSortStatus = ""
end

function MercenaryTabClass:BuildSupportList(selectedData)
	local supportList = { { label = "<No support>", id = nil } }
	for _, supportId in ipairs(selectedData and selectedData.possibleSupportIds or { }) do
		local support = self.data.supports[supportId]
		if support then
			t_insert(supportList, { id = supportId, tier = support.variant, label = supportLabel(support) })
		end
	end
	return supportList
end

function MercenaryTabClass:RefreshSupportLists()
	local selected = self.profile.skills[self.selectedSkillIndex]
	local selectedData = selected and self.data.skills[selected.id]
	local supportList = self:BuildSupportList(selectedData)
	local maxSupports = MercenaryTools.supportLimit(self.data, selectedData)
	for index, control in ipairs(self.supportControls) do
		control:SetList(copyTable(supportList, true))
		control:SelByValue(selected and selected.supports[index] and selected.supports[index].id, "id")
		control.enabled = selected ~= nil
		control.shown = index <= maxSupports
		self.controls["support"..index.."Clear"].shown = control.shown
	end
end

local function supportDPS(output, field)
	if not output then return 0 end
	return (field == "FullDPS" and output.FullDPS ~= nil and output.FullDPS)
		or (output.Minion and output.Minion.CombinedDPS)
		or (output[field] ~= nil and output[field])
		or 0
end

function MercenaryTabClass:ApplySupportSort(index, list)
	local control = self.supportControls[index]
	if not control then return end
	control:SetList(copyTable(list, true))
	local selected = self.profile.skills[self.selectedSkillIndex]
	control:SelByValue(selected and selected.supports[index] and selected.supports[index].id, "id")
end

function MercenaryTabClass:QueueSupportSort(index)
	if not self.sortGemsByDPS then return end
	local control = self.supportControls[index]
	local selected = self.profile.skills[self.selectedSkillIndex]
	if not control or not selected or not control.list or #control.list < 2 then return end
	local key = table.concat({ self.supportSortRevision, self.build.outputRevision or 0, selected.id, index, self.sortGemsByDPSField }, ":")
	local cached = self.supportSortCache[index]
	if cached and cached.key == key then
		self:ApplySupportSort(index, cached.list)
		return
	end
	local originalList = copyTable(control.list, true)
	local revision = self.supportSortRevision
	local skillIndex = self.selectedSkillIndex
	self.supportSortStatus = "0%"
	self.supportSortCoroutine = coroutine.create(function()
		local calcTab = self.build.calcsTab
		local calcFunc = calcTab and calcTab.GetMiscCalculator and select(1, calcTab:GetMiscCalculator())
		if not calcFunc then return end
		local useFullDPS = self.sortGemsByDPSField == "FullDPS"
		local startTime = GetTime()
		for entryIndex, entry in ipairs(originalList) do
			local oldSupport = selected.supports[index]
			selected.supports[index] = entry.id and { id = entry.id, tier = entry.tier } or nil
			local ok, output = pcall(calcFunc, { comparisonActor = "MERCENARY" }, useFullDPS)
			selected.supports[index] = oldSupport
			if not ok then error(output) end
			entry.dps = supportDPS(output, self.sortGemsByDPSField)
			self.supportSortStatus = ("%d%%"):format(m_floor(entryIndex / #originalList * 100))
			if GetTime() - startTime > 50 then
				coroutine.yield()
				startTime = GetTime()
			end
		end
		t_sort(originalList, function(a, b)
			if a.dps ~= b.dps then return a.dps > b.dps end
			local aLabel, bLabel = StripEscapes(a.label or ""), StripEscapes(b.label or "")
			return aLabel == bLabel and tostring(a.id or "") < tostring(b.id or "") or aLabel < bLabel
		end)
		self.supportSortCache[index] = { key = key, list = originalList }
		self.supportSortStatus = ""
		if self.supportSortRevision == revision and self.selectedSkillIndex == skillIndex then
			self:ApplySupportSort(index, originalList)
		end
	end)
end

function MercenaryTabClass:ProcessSupportSort()
	if not self.supportSortCoroutine then return end
	local ok, err = coroutine.resume(self.supportSortCoroutine)
	if launch.devMode and not ok then error(err) end
	if coroutine.status(self.supportSortCoroutine) == "dead" then
		self.supportSortCoroutine = nil
		self.supportSortStatus = ""
	end
end

function MercenaryTabClass:RefreshControls()
	local setList = { }
	for _, setId in ipairs(self.mercenarySetOrderList) do
		local set = self.mercenarySets[setId]
		if set then
			t_insert(setList, { id = setId, label = set.title or "Default" })
		end
	end
	self.controls.setSelect:SetList(setList)
	self.controls.setSelect:SelByValue(self.activeMercenarySetId, "id")

	local classGroup = self.classGroupsByClassId[self.profile.classId]
	self.controls.class:SelByValue(classGroup and classGroup.id, "id")

	local builds = { }
	for _, buildId in ipairs(classGroup and classGroup.buildIds or { }) do
		local mercBuild = self.data.builds[buildId]
		t_insert(builds, { id = buildId, classId = mercBuild.classId, label = mercBuild.name })
	end
	self.controls.build:SetList(builds)
	self.controls.build:SelByValue(self.profile.buildId, "id")
	self.controls.level:SetText(tostring(self.profile.foundAreaLevel or 0), false)
	self.controls.lifeComparison:SelByValue(self.profile.lifeComparison or "AUTO", "id")

	local skillList = { { label = "<No skill>", id = nil } }
	local mercBuild = self.data.builds[self.profile.buildId]
	for _, skillId in ipairs(mercBuild and mercBuild.skillIds or { }) do
		local skill = self.data.skills[skillId]
		local skillEffect = self.build.data.skills[skillId]
		t_insert(skillList, { id = skillId, label = gemColorLabel(skillEffect and skillEffect.color)..skill.name })
	end
	self.skillOptions = skillList
	self.controls.skillList.list = self.profile.skills
	if #self.profile.skills > 0 then
		self.selectedSkillIndex = m_min(m_max(self.selectedSkillIndex or 1, 1), #self.profile.skills)
	else
		self.selectedSkillIndex = 1
	end
	local selected = self.profile.skills[self.selectedSkillIndex]
	self.controls.skillList.selIndex = selected and self.selectedSkillIndex or nil
	self.controls.skillList.selValue = selected
	self.controls.skill:SetList(skillList)
	self.controls.skill:SelByValue(selected and selected.id, "id")
	self.controls.skillEnabled.state = selected and selected.enabled ~= false or false
	self.controls.skillFullDPS.state = selected and selected.includeInFullDPS or false
	self.controls.skillCount:SetText(tostring(selected and selected.count or 1), false)
	local selectedData = selected and self.data.skills[selected.id]
	local selectedEffect = selected and self.build.data.skills[selected.id]
	local partList = { }
	for index, part in ipairs(selectedEffect and selectedEffect.parts or { }) do
		t_insert(partList, { index = index, label = part.name or "Part "..index })
	end
	if #partList == 0 then partList[1] = { index = 1, label = "Default" } end
	self.controls.skillPart:SetList(partList)
	self.controls.skillPart:SelByValue(selected and selected.skillPart or self.build.data.mercenaryStatData.defaultSkillParts[selected and selected.id] or 1, "index")
	self.controls.skillPart.enabled = #partList > 1
	local minionSkillList = { }
	local minionId = selected and self.data.summonedMinions and self.data.summonedMinions[selected.id]
	local minion = minionId and self.build.data.minions[minionId]
	for _, skillId in ipairs(minion and minion.skillList or { }) do
		local minionSkill = self.build.data.skills[skillId]
		if minionSkill then t_insert(minionSkillList, { index = #minionSkillList + 1, label = minionSkill.name }) end
	end
	self.controls.skillMinionSkill:SetList(minionSkillList)
	self.controls.skillMinionSkill:SelByValue(selected and selected.skillMinionSkill or 1, "index")
	self.controls.skillMinionSkill.enabled = #minionSkillList > 1
	self.controls.skillMinionSkill.shown = #minionSkillList > 0
	self.controls.skillMinionSkillLabel.shown = #minionSkillList > 0
	self.controls.sortGemsByDPS.state = self.sortGemsByDPS
	self.controls.sortGemsByDPSFieldControl:SelByValue(self.sortGemsByDPSField, "type")
	self:RefreshSupportLists()
	self:RefreshErrors()
end

function MercenaryTabClass:AddSkill()
	local firstSkill = self.skillOptions and self.skillOptions[2]
	if firstSkill then
		self:SetSkill(#self.profile.skills + 1, firstSkill.id)
	end
end

function MercenaryTabClass:NewMercenarySet(setId, title)
	local set = {
		id = setId,
		title = title,
		foundAreaLevel = 68,
		skills = { },
		lifeComparison = "AUTO",
	}
	if not set.id then
		set.id = 1
		while self.mercenarySets[set.id] do
			set.id = set.id + 1
		end
	end
	self.mercenarySets[set.id] = set
	return set
end

function MercenaryTabClass:SetActiveMercenarySet(setId)
	if not self.mercenarySetOrderList[1] then
		self.mercenarySetOrderList[1] = 1
		self:NewMercenarySet(1)
	end

	if self.activeMercenarySetId and self.profile and self.mercenarySets[self.activeMercenarySetId] then
		self.profile.id = self.activeMercenarySetId
		self.mercenarySets[self.activeMercenarySetId] = self.profile
	end
	if not setId or not self.mercenarySets[setId] then
		setId = self.mercenarySetOrderList[1]
	end

	self.activeMercenarySetId = setId
	self.profile = self.mercenarySets[setId]
	self.selectedSkillIndex = 1
	self.modFlag = true
	self.build.buildFlag = true
	if self.controls.skillList then
		self:RefreshControls()
	end
end

function MercenaryTabClass:OpenMercenarySetManagePopup()
	main:OpenPopup(370, 290, "Manage Mercenary Loadouts", {
		new("MercenarySetListControl", nil, {0, 50, 350, 200}, self),
		new("ButtonControl", nil, {0, 260, 90, 20}, "Done", function()
			main:ClosePopup()
		end),
	})
end

function MercenaryTabClass:SetSkill(index, skillId)
	self.selectedSkillIndex = index
	local existing = self.profile.skills[index]
	local wasMainSkill = existing and self.profile.mainSkillId == existing.id
	if not skillId then
		table.remove(self.profile.skills, index)
		if wasMainSkill then self.profile.mainSkillId = nil end
		self.selectedSkillIndex = m_min(index, m_max(#self.profile.skills, 1))
	else
		self.profile.skills[index] = existing and existing.id == skillId and existing or {
			id = skillId,
			enabled = true,
			includeInFullDPS = false,
			count = 1,
			supports = { },
		}
		if wasMainSkill or not self.profile.mainSkillId then self.profile.mainSkillId = skillId end
	end
	self:Changed()
end

function MercenaryTabClass:SetSupport(index, supportId)
	local skill = self.profile.skills[self.selectedSkillIndex]
	if not skill then return end
	if supportId then
		local support = self.data.supports[supportId]
		skill.supports[m_min(index, #skill.supports + 1)] = { id = supportId, tier = support.variant }
	elseif skill.supports[index] then
		table.remove(skill.supports, index)
	end
	self:Changed()
end

function MercenaryTabClass:Reset()
	self.profile = self:NewMercenarySet(self.activeMercenarySetId, self.profile.title)
	self.selectedSkillIndex = 1
	self:Changed()
end

function MercenaryTabClass:IsSlotSupported(slotName)
	local parentSlot = slotName:match("^(.-) Abyssal Socket %d+$")
	return SUPPORTED_SLOTS[parentSlot or slotName] == true
end

-- Mercenary permissions are granted by parsed modifiers, so they are read from the
-- modifier database built by the last calculation rather than from tree node names.
function MercenaryTabClass:PlayerFlag(flagName)
	-- The tab can be asked to validate items before the first calculation has run.
	local mainEnv = self.build.calcsTab and self.build.calcsTab.mainEnv
	return mainEnv and mainEnv.modDB and mainEnv.modDB:Flag(nil, flagName) or false
end

function MercenaryTabClass:ValidateEquippedItem(item, slotName, itemSet)
	if not self:IsSlotSupported(slotName) then
		return false, "slot is not supported by Mercenaries"
	end
	local parentSlot, abyssalSocketIndex = slotName:match("^(.-) Abyssal Socket (%d+)$")
	if parentSlot then
		local parentSetSlot = itemSet[MercenaryTools.itemSlotName(parentSlot)]
		local parentItem = self.build.itemsTab.items[parentSetSlot and parentSetSlot.selItemId]
		if not parentItem or (parentItem.abyssalSocketCount or 0) < tonumber(abyssalSocketIndex) then
			return false, "parent item does not have this Abyssal Socket"
		end
	end
	local mercBuild = self.data.builds[self.profile.buildId]
	local class = mercBuild and self.data.classes[mercBuild.classId]
	if not mercBuild or not class then
		return false, "select a Mercenary build first"
	end
	if ARMOUR_SLOTS[slotName] then
		local itemRequirements = item.requirements or { }
		local attributes = class.attributeId or ""
		local attributeCount, requiredAttributeCount, hasAssociatedRequirement = 0, 0, false
		for _, attribute in ipairs({ "Str", "Dex", "Int" }) do
			if attributes:find(attribute, 1, true) then attributeCount = attributeCount + 1 end
		end
		for _, requirement in ipairs({ { "Str", "str" }, { "Dex", "dex" }, { "Int", "int" } }) do
			local required = (itemRequirements[requirement[2]] or 0) > 0
			local associated = attributes:find(requirement[1], 1, true) ~= nil
			if required then
				requiredAttributeCount = requiredAttributeCount + 1
				hasAssociatedRequirement = hasAssociatedRequirement or associated
			end
			if attributeCount > 1 and required and not associated then
				return false, "armour attribute alignment does not match "..class.attributeName
			end
		end
		if attributeCount == 1 and (not hasAssociatedRequirement or requiredAttributeCount > 2) then
			return false, "armour attribute alignment does not match "..class.attributeName
		end
	end
	local requiredFoundLevel = MercenaryTools.requiredFoundAreaLevel(item.requirements and item.requirements.level)
	if (self.profile.foundAreaLevel or 0) < requiredFoundLevel then
		return false, "requires found-area level "..requiredFoundLevel
	end
	if item.rarity == "UNIQUE" or item.rarity == "RELIC" then
		local requiredFlag = UNIQUE_FLAG_BY_SLOT[slotName]
		if not requiredFlag then
			return false, "Unique items are never permitted in this slot"
		elseif not self:PlayerFlag(requiredFlag) then
			return false, "requires a modifier allowing your Mercenary to equip "..UNIQUE_SLOT_DESCRIPTION[requiredFlag]
		end
	end
	if slotName == "Weapon 1" or slotName == "Weapon 2" then
		local allowedTypes = slotName == "Weapon 1" and mercBuild.weaponConfiguration.mainHandTypes or mercBuild.weaponConfiguration.offHandTypes
		if not MercenaryTools.contains(allowedTypes, item.type) then
			return false, item.type.." is not valid in this weapon slot for the selected build"
		end
	end
	if #(item.grantedSkills or { }) > 0 then
		return false, "item-granted skills and triggers cannot be used"
	end
	if itemSet then
		for playerSlotName, playerSlot in pairs(itemSet) do
			if type(playerSlot) == "table" and not MercenaryTools.baseItemSlotName(playerSlotName) and playerSlot.selItemId == item.id then
				return false, "the same physical item is equipped by the player"
			end
		end
	end
	return true
end

function MercenaryTabClass:GetErrors()
	local errors = MercenaryTools.validateProfile(self.profile, self.data)
	if not self:PlayerFlag("CanHirePermanentMercenary") then
		t_insert(errors, "Permanently hiring a Mercenary requires Noble Blood, from the Scion's Luminary ascendancy")
	end
	if (self.profile.foundAreaLevel or 0) >= self.build.characterLevel + 20 then
		t_insert(errors, "Character level is at least 20 below the found-area level")
	end
	local mercBuild = self.data.builds[self.profile.buildId]
	if mercBuild and #mercBuild.weaponTypes == 0 then
		t_insert(errors, "Selected build has no exported wieldable-type data")
	end
	local itemsTab = self.build.itemsTab
	local itemSet = itemsTab.activeItemSet
	if not itemSet then
		t_insert(errors, "No active item set is available")
	else
		local offHandSlot = itemSet[MercenaryTools.itemSlotName("Weapon 2")]
		if mercBuild and mercBuild.weaponConfiguration.offHandRequired and not itemsTab.items[offHandSlot and offHandSlot.selItemId] then
			t_insert(errors, "Weapon 2: selected build requires a "..table.concat(mercBuild.weaponConfiguration.offHandTypes, " or "))
		end
		for _, slot in ipairs(itemsTab.mercenarySlots) do
			local setSlot = itemSet[slot.slotName]
			local item = itemsTab.items[setSlot and setSlot.selItemId]
			if item then
				local baseValid = itemsTab:IsItemValidForSlot(item, slot.slotName, itemSet)
				local valid, reason = self:ValidateEquippedItem(item, slot.mercenarySlotName, itemSet)
				if not baseValid then
					t_insert(errors, slot.mercenarySlotName..": invalid base slot or weapon configuration")
				elseif not valid then
					t_insert(errors, slot.mercenarySlotName..": "..reason)
				end
			end
		end
	end
	local mainEnv = self.build.calcsTab and self.build.calcsTab.mainEnv
	for _, calculationError in ipairs(mainEnv and mainEnv.mercenaryCalculationErrors or { }) do
		t_insert(errors, calculationError)
	end
	return errors
end

function MercenaryTabClass:RefreshErrors()
	wipeTable(self.errors)
	for _, errorText in ipairs(self:GetErrors()) do
		t_insert(self.errors, { colorCodes.WARNING..errorText, height = 16 })
	end
	if #self.errors == 0 then
		t_insert(self.errors, { colorCodes.POSITIVE.."No configuration warnings", height = 16 })
	end
end

function MercenaryTabClass:Load(xml)
	local function loadSkill(node, profile)
		local skill = {
			id = node.attrib.id,
			enabled = node.attrib.enabled ~= "false",
			includeInFullDPS = node.attrib.includeInFullDPS == "true",
			count = tonumber(node.attrib.count) or node.attrib.count or 1,
			skillPart = tonumber(node.attrib.skillPart),
			skillStageCount = tonumber(node.attrib.skillStageCount),
			skillMineCount = tonumber(node.attrib.skillMineCount),
			skillMinionSkill = tonumber(node.attrib.skillMinionSkill),
			supports = { },
		}
		for _, supportNode in ipairs(node) do
			if supportNode.elem == "Support" then
				t_insert(skill.supports, { id = supportNode.attrib.id, tier = tonumber(supportNode.attrib.tier) })
			end
		end
		t_insert(profile.skills, skill)
	end
	local function loadProfile(node, profile)
		profile.buildId = node.attrib.buildId
		profile.foundAreaLevel = tonumber(node.attrib.foundAreaLevel) or 68
		profile.mainSkillId = node.attrib.mainSkillId
		profile.lifeComparison = node.attrib.lifeComparison or "AUTO"
		local mercBuild = self.data.builds[profile.buildId]
		profile.classId = mercBuild and mercBuild.classId
		for _, child in ipairs(node) do
			if child.elem == "Skill" then loadSkill(child, profile) end
		end
	end

	self.activeMercenarySetId = nil
	self.profile = nil
	self.mercenarySets = { }
	self.mercenarySetOrderList = { }
	if xml.attrib.sortGemsByDPS then
		self.sortGemsByDPS = xml.attrib.sortGemsByDPS ~= "false"
	end
	self.controls.sortGemsByDPS.state = self.sortGemsByDPS
	self.controls.sortGemsByDPSFieldControl:SelByValue(xml.attrib.sortGemsByDPSField or "CombinedDPS", "type")
	self.sortGemsByDPSField = self.controls.sortGemsByDPSFieldControl:GetSelValueByKey("type")
	local loadedSets = false
	for _, child in ipairs(xml) do
		if child.elem == "MercenarySet" then
			local setId = tonumber(child.attrib.id) or 1
			while self.mercenarySets[setId] do setId = setId + 1 end
			local profile = self:NewMercenarySet(setId, child.attrib.title)
			loadProfile(child, profile)
			t_insert(self.mercenarySetOrderList, setId)
			loadedSets = true
		end
	end
	if not loadedSets then
		local profile = self:NewMercenarySet(1)
		loadProfile(xml, profile)
		t_insert(self.mercenarySetOrderList, 1)
	end
	self:SetActiveMercenarySet(tonumber(xml.attrib.activeMercenarySet) or 1)
	self.modFlag = false
	self:RefreshControls()
end

function MercenaryTabClass:Save(xml)
	xml.attrib = {
		activeMercenarySet = tostring(self.activeMercenarySetId),
		sortGemsByDPS = tostring(self.sortGemsByDPS),
		sortGemsByDPSField = self.sortGemsByDPSField,
	}
	if self.activeMercenarySetId and self.profile then
		self.profile.id = self.activeMercenarySetId
		self.mercenarySets[self.activeMercenarySetId] = self.profile
	end
	for _, setId in ipairs(self.mercenarySetOrderList) do
		local profile = self.mercenarySets[setId]
		if profile then
			local setNode = { elem = "MercenarySet", attrib = {
				id = tostring(setId),
				title = profile.title,
				buildId = profile.buildId,
				foundAreaLevel = tostring(profile.foundAreaLevel or 68),
				mainSkillId = profile.mainSkillId,
				lifeComparison = profile.lifeComparison,
			} }
			for _, skill in ipairs(profile.skills or { }) do
				local child = { elem = "Skill", attrib = {
					id = skill.id,
					enabled = tostring(skill.enabled ~= false),
					includeInFullDPS = tostring(skill.includeInFullDPS == true),
					count = tostring(skill.count or 1),
					skillPart = skill.skillPart and tostring(skill.skillPart),
					skillStageCount = skill.skillStageCount and tostring(skill.skillStageCount),
					skillMineCount = skill.skillMineCount and tostring(skill.skillMineCount),
					skillMinionSkill = skill.skillMinionSkill and tostring(skill.skillMinionSkill),
				} }
				for _, support in ipairs(skill.supports or { }) do
					t_insert(child, { elem = "Support", attrib = { id = support.id, tier = tostring(support.tier) } })
				end
				t_insert(setNode, child)
			end
			t_insert(xml, setNode)
		end
	end
	self.modFlag = false
end

function MercenaryTabClass:Draw(viewPort, inputEvents)
	self.x, self.y, self.width, self.height = viewPort.x, viewPort.y, viewPort.width, viewPort.height
	self:ProcessSupportSort()
	self:RefreshErrors()
	self:ProcessControlsInput(inputEvents, viewPort)
	main:DrawBackground(viewPort)
	self:DrawControls(viewPort)
end
