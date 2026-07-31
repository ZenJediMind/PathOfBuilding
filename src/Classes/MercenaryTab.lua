-- Path of Building
--
-- Class: Mercenary Tab
-- Permanent Mercenary configuration, persistence, import, and equipment validation.
--
local MercenaryTools = require("Modules/MercenaryTools")

local t_insert = table.insert
local m_min = math.min
local m_max = math.max

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
	self.ListControl(anchor, rect, 20, "VERTICAL", true, mercenaryTab.profile.skills)
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
	local label = skillData and skillData.name or skill.id or "?"
	if skill.enabled == false then label = colorCodes.NEGATIVE..label.." (Disabled)" end
	if self.mercenaryTab.profile.mainSkillId == skill.id then label = label..colorCodes.RELIC.." (Calcs)" end
	if skill.includeInFullDPS then label = label..colorCodes.CUSTOM.." (FullDPS)" end
	if #(skill.supports or { }) > 0 then label = label.." ^7+ "..#skill.supports.." support"..(#skill.supports == 1 and "" or "s") end
	return label
end

function MercenarySkillListClass:OnSelect(index)
	self.mercenaryTab.selectedSkillIndex = index
	self.mercenaryTab:RefreshControls()
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
	self.profile = {
		foundAreaLevel = 68,
		skills = { },
		lifeComparison = "AUTO",
	}
	self.selectedSkillIndex = 1
	self.errors = { }
	self.importError = nil

	self.controls.classLabel = new("LabelControl", { "TOPLEFT", self, "TOPLEFT" }, { 12, 12, 0, 16 }, "^7Mercenary class:")
	self.controls.class = new("DropDownControl", { "LEFT", self.controls.classLabel, "RIGHT" }, { 8, 0, 240, 20 }, { }, function(_, value)
		self.profile.classId = value and value.id
		self.profile.buildId = nil
		self.profile.skills = { }
		self.profile.mainSkillId = nil
		self.selectedSkillIndex = 1
		self:Changed()
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
	self.controls.skillDetailAnchor = new("Control", { "TOPLEFT", self.controls.skillList, "TOPRIGHT" }, { 20, 0, 0, 0 })
	self.controls.skillDetailAnchor.shown = function()
		return self.profile.skills[self.selectedSkillIndex] ~= nil
	end
	self.controls.skillLabel = new("LabelControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 0, 2, 0, 16 }, "^7Skill:")
	self.controls.skill = new("DropDownControl", { "TOPLEFT", self.controls.skillDetailAnchor, "TOPLEFT" }, { 85, 0, 380, 20 }, { }, function(_, value)
		self:SetSkill(self.selectedSkillIndex, value and value.id)
	end)
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
		self.controls["support"..index.."Clear"] = clear
		self.controls["support"..index] = control
		return control
	end
	for index = 1, MercenaryTools.maxSupportLimit(self.data) do
		self.supportControls[index] = createSupportRow(index)
	end

	self.controls.warrantLabel = new("LabelControl", { "TOPLEFT", self.controls.skillList, "BOTTOMLEFT" }, { 0, 40, 0, 16 }, "^7Warrant item JSON:")
	self.controls.warrant = new("EditControl", { "TOPLEFT", self.controls.warrantLabel, "BOTTOMLEFT" }, { 0, 4, 620, 84 }, "", nil, "\t\n", nil, nil, 14, true)
	self.controls.importWarrant = new("ButtonControl", { "TOPLEFT", self.controls.warrant, "TOPRIGHT" }, { 8, 0, 125, 20 }, "Import Warrant", function()
		self:ImportWarrant()
	end)
	self.controls.errorsHeader = new("LabelControl", { "TOPLEFT", self.controls.warrant, "BOTTOMLEFT" }, { 0, 12, 0, 16 }, "^7Warnings (informational):")
	self.controls.errors = new("TextListControl", { "TOPLEFT", self.controls.errorsHeader, "BOTTOMLEFT" }, { 0, 4, 760, 110 }, { { x = 4, align = "LEFT" } }, self.errors)
	self:RefreshControls()
end)

function MercenaryTabClass:Changed()
	self.modFlag = true
	self.build.buildFlag = true
	self:RefreshControls()
end

function MercenaryTabClass:RefreshControls()
	local classes = { }
	for _, classId in ipairs(self.data.classOrder) do
		local class = self.data.classes[classId]
		t_insert(classes, { id = classId, label = class.name:gsub("^%[DNT%]%s*", "").." ("..class.attributeName..")" })
	end
	self.controls.class:SetList(classes)
	self.controls.class:SelByValue(self.profile.classId, "id")

	local builds = { }
	local class = self.data.classes[self.profile.classId]
	for _, buildId in ipairs(class and class.buildIds or { }) do
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
		t_insert(skillList, { id = skillId, label = skill.name })
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
	local supportList = { { label = "<No support>", id = nil } }
	for _, supportId in ipairs(selectedData and selectedData.possibleSupportIds or { }) do
		local support = self.data.supports[supportId]
		t_insert(supportList, { id = supportId, label = support.name.." (Tier "..support.variant..")" })
	end
	local maxSupports = MercenaryTools.supportLimit(self.data, selectedData)
	for index, control in ipairs(self.supportControls) do
		control:SetList(supportList)
		control:SelByValue(selected and selected.supports[index] and selected.supports[index].id, "id")
		control.enabled = selected ~= nil
		-- Only offer as many rows as the selected skill accepts supports.
		control.shown = index <= maxSupports
		self.controls["support"..index.."Clear"].shown = control.shown
	end
	self:RefreshErrors()
end

function MercenaryTabClass:AddSkill()
	local firstSkill = self.skillOptions and self.skillOptions[2]
	if firstSkill then
		self:SetSkill(#self.profile.skills + 1, firstSkill.id)
	end
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

function MercenaryTabClass:ImportWarrant()
	self.importError = nil
	local imported, err = MercenaryTools.importWarrant(self.controls.warrant.buf, self.data, self.profile.classId)
	if not imported then
		self.importError = err
		self:RefreshErrors()
		return
	end
	local matchingBuilds = { }
	local class = self.data.classes[self.profile.classId]
	for _, buildId in ipairs(class.buildIds) do
		local mercBuild = self.data.builds[buildId]
		local matches = true
		for _, skill in ipairs(imported.skills) do
			matches = matches and MercenaryTools.contains(mercBuild.skillIds, skill.id)
		end
		if matches then t_insert(matchingBuilds, buildId) end
	end
	if self.profile.buildId and MercenaryTools.contains(matchingBuilds, self.profile.buildId) then
		matchingBuilds = { self.profile.buildId }
	end
	if #matchingBuilds ~= 1 then
		self.importError = #matchingBuilds == 0 and "Warrant skills do not match a build for the selected class" or "Warrant skills match multiple builds; select the exact build first"
		self:RefreshErrors()
		return
	end
	local importedSkills = MercenaryTools.copyImportedSkills(imported)
	local candidate = {
		buildId = matchingBuilds[1],
		foundAreaLevel = self.profile.foundAreaLevel,
		mainSkillId = importedSkills[1].id,
		skills = importedSkills,
	}
	local candidateErrors = MercenaryTools.validateProfile(candidate, self.data)
	if #candidateErrors > 0 then
		self.importError = table.concat(candidateErrors, "; ")
		self:RefreshErrors()
		return
	end
	self.profile.buildId = candidate.buildId
	self.profile.skills = candidate.skills
	self.profile.mainSkillId = candidate.mainSkillId
	self.selectedSkillIndex = 1
	self.controls.warrant:SetText("")
	self:Changed()
end

function MercenaryTabClass:Reset()
	self.profile = { foundAreaLevel = 68, skills = { }, lifeComparison = "AUTO" }
	self.selectedSkillIndex = 1
	self.importError = nil
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
	if self.importError then t_insert(errors, self.importError) end
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
	self.profile = {
		buildId = xml.attrib.buildId,
		foundAreaLevel = tonumber(xml.attrib.foundAreaLevel) or 68,
		mainSkillId = xml.attrib.mainSkillId,
		lifeComparison = xml.attrib.lifeComparison or "AUTO",
		skills = { },
	}
	local mercBuild = self.data.builds[self.profile.buildId]
	self.profile.classId = mercBuild and mercBuild.classId
	for _, child in ipairs(xml) do
		if child.elem == "Skill" then
			local skill = {
				id = child.attrib.id,
				enabled = child.attrib.enabled ~= "false",
				includeInFullDPS = child.attrib.includeInFullDPS == "true",
				count = tonumber(child.attrib.count) or child.attrib.count or 1,
				skillPart = tonumber(child.attrib.skillPart),
				skillStageCount = tonumber(child.attrib.skillStageCount),
				skillMineCount = tonumber(child.attrib.skillMineCount),
				skillMinionSkill = tonumber(child.attrib.skillMinionSkill),
				supports = { },
			}
			for _, supportNode in ipairs(child) do
				if supportNode.elem == "Support" then
					t_insert(skill.supports, { id = supportNode.attrib.id, tier = tonumber(supportNode.attrib.tier) })
				end
			end
			t_insert(self.profile.skills, skill)
		end
	end
	self.modFlag = false
	self:RefreshControls()
end

function MercenaryTabClass:Save(xml)
	xml.attrib = {
		buildId = self.profile.buildId,
		foundAreaLevel = tostring(self.profile.foundAreaLevel or 68),
		mainSkillId = self.profile.mainSkillId,
		lifeComparison = self.profile.lifeComparison,
	}
	for _, skill in ipairs(self.profile.skills) do
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
		t_insert(xml, child)
	end
	self.modFlag = false
end

function MercenaryTabClass:Draw(viewPort, inputEvents)
	self.x, self.y, self.width, self.height = viewPort.x, viewPort.y, viewPort.width, viewPort.height
	self:RefreshErrors()
	self:ProcessControlsInput(inputEvents, viewPort)
	main:DrawBackground(viewPort)
	self:DrawControls(viewPort)
end
