local MercenaryTools = { }

MercenaryTools.equipmentSlots = { "Weapon 1", "Weapon 2", "Helmet", "Body Armour", "Gloves", "Boots", "Amulet", "Ring 1", "Ring 2", "Belt" }

function MercenaryTools.itemSlotName(slotName)
	return "Mercenary "..slotName
end

function MercenaryTools.baseItemSlotName(slotName)
	return type(slotName) == "string" and slotName:match("^Mercenary (.+)$") or nil
end

function MercenaryTools.comparisonBaseOutput(playerOutput, actorOutputs, slotName)
	local actor = MercenaryTools.baseItemSlotName(slotName) and "MERCENARY" or "PLAYER"
	return actorOutputs and actorOutputs[actor] or playerOutput
end

local MAX_WARRANT_BYTES = 256 * 1024
local MAX_SKILLS = 6

function MercenaryTools.contains(values, wanted)
	for _, value in ipairs(values or { }) do
		if value == wanted then
			return true
		end
	end
	return false
end
local contains = MercenaryTools.contains

function MercenaryTools.classGroups(mercenaryData)
	local groups = { }
	local groupsByClassId = { }
	local groupsByLabel = { }
	for _, classId in ipairs(mercenaryData.classOrder or { }) do
		local class = mercenaryData.classes[classId]
		local name = class.name:gsub("^%[DNT%]%s*", "")
		name = name:gsub("^Merc ", ""):gsub(" Merc ", " "):gsub("%s+%d+$", "")
		local label = name.." ("..class.attributeName..")"
		local group = groupsByLabel[label]
		if not group then
			group = { id = label, label = label, classIds = { }, buildIds = { } }
			groupsByLabel[label] = group
			table.insert(groups, group)
		end
		table.insert(group.classIds, classId)
		groupsByClassId[classId] = group
		for _, buildId in ipairs(class.buildIds or { }) do
			table.insert(group.buildIds, buildId)
		end
	end
	return groups, groupsByClassId
end

-- How many supports a skill accepts, and the largest limit any skill accepts. Both
-- come from the hand-authored `supportCounts` policy attached to the Mercenary data.
function MercenaryTools.supportLimit(mercenaryData, skill)
	local count = skill and mercenaryData.supportCounts[skill.supportCountId]
	if not count then
		return 0
	end
	return count.maximum
end

function MercenaryTools.maxSupportLimit(mercenaryData)
	local maximum = 0
	for _, count in pairs(mercenaryData.supportCounts) do
		maximum = math.max(maximum, count.maximum)
	end
	return maximum
end
local supportLimit = MercenaryTools.supportLimit

function MercenaryTools.skillLevel(grantedEffect, actorLevel)
	local bestLevel, bestRequirement = 1, -1
	for level, levelData in pairs(grantedEffect and grantedEffect.levels or { }) do
		local requirement = levelData.levelRequirement or 1
		if type(level) == "number" and requirement <= actorLevel and (requirement > bestRequirement or requirement == bestRequirement and level > bestLevel) then
			bestLevel, bestRequirement = level, requirement
		end
	end
	return bestLevel
end

local function listProducesSkillData(mods, key)
	for _, modOrGroup in ipairs(mods or { }) do
		for _, mod in ipairs(modOrGroup.name and { modOrGroup } or modOrGroup) do
			if mod.name == "SkillData" and type(mod.value) == "table" and mod.value.key == key then
				return true
			end
		end
	end
	return false
end

local function producesSkillData(grantedEffect, key)
	if listProducesSkillData(grantedEffect.baseMods, key) then
		return true
	end
	local function statProduces(statId)
		local map = grantedEffect.statMap[statId]
		return map ~= nil and listProducesSkillData(map, key)
	end
	for _, statId in ipairs(grantedEffect.stats or { }) do
		if statProduces(statId) then return true end
	end
	for _, stat in ipairs(grantedEffect.constantStats or { }) do
		if statProduces(stat[1]) then return true end
	end
	-- Quality stats are deliberately not consulted: a Mercenary skill is not a gem and
	-- always has quality 0, so anything only a quality stat produces stays nil.
	return false
end

-- Which declared inputs of the base skill's `preDamageFunc` this Mercenary skill cannot
-- populate from its own stats, or nil when the base declares no inputs at all.
function MercenaryTools.missingPreDamageFuncInputs(grantedEffect, baseSkillId, mercenaryStatData)
	local declared = mercenaryStatData.preDamageFuncInputs[baseSkillId]
	if not declared then
		return nil
	end
	local missing = { }
	for _, key in ipairs(declared) do
		if not producesSkillData(grantedEffect, key) then table.insert(missing, key) end
	end
	return missing
end

-- Report every declared input of an inherited `preDamageFunc` that the Mercenary
-- skill's own stats cannot populate. Without this the function reads nil, which
-- either errors or reports the missing damage component as zero.
-- A Mercenary skill that overrides `preDamageFunc` itself is not checked, because that
-- function was written against the stats the Mercenary version actually has.
function MercenaryTools.preDamageFuncErrors(grantedEffect, baseEffect, mercenaryStatData)
	if not grantedEffect.preDamageFunc or not grantedEffect.inheritedFrom
	  or grantedEffect.preDamageFunc ~= (baseEffect and baseEffect.preDamageFunc) then
		return nil
	end
	local missing = MercenaryTools.missingPreDamageFuncInputs(grantedEffect, grantedEffect.inheritedFrom, mercenaryStatData)
	if not missing then
		return { "Undeclared preDamageFunc inputs for "..grantedEffect.inheritedFrom.." (inherited by "..grantedEffect.id..")" }
	end
	local errors
	for _, key in ipairs(missing) do
		errors = errors or { }
		table.insert(errors, "Mercenary skill "..grantedEffect.id.." has no stat for "..key..", required by the "..grantedEffect.inheritedFrom.." preDamageFunc")
	end
	return errors
end

-- A Mercenary is as strong as the area it was found in, and levels up with the areas
-- it is taken to, but stops gaining levels past the level of the highest-level
-- non-endgame area (GGG patch notes: "up to a maximum of level 68"). Found-area
-- level itself is not limited by that ceiling — map Mercenaries keep their high
-- found-area level — but monster damage/armour/evasion tables only exist for 1–100.
local MERCENARY_AREA_SCALING_CAP = 68
local MERCENARY_LEVEL_MAX = 100
-- A Mercenary can equip an item requiring up to this fraction more than the level
-- of the area it was found in.
local FOUND_AREA_LEVEL_REQUIREMENT_RATIO = 0.7

function MercenaryTools.effectiveLevel(foundAreaLevel, currentAreaLevel)
	local found = math.max(1, math.min(tonumber(foundAreaLevel) or 1, MERCENARY_LEVEL_MAX))
	local current = math.max(1, math.min(tonumber(currentAreaLevel) or 1, MERCENARY_AREA_SCALING_CAP))
	return math.max(found, current)
end

function MercenaryTools.requiredFoundAreaLevel(requiredLevel)
	return math.ceil((tonumber(requiredLevel) or 0) * FOUND_AREA_LEVEL_REQUIREMENT_RATIO)
end

-- MercenaryBuildExtraStats exports the three values but not their tier boundaries.
-- Keep the validated runtime tier policy here until those boundaries are exposed.
-- Values are truncated because passive mods are integer values.
MercenaryTools.PASSIVE_STAT_LEVELS = { 24, 68, 84 }

function MercenaryTools.passiveStatValue(values, level)
	local levels = MercenaryTools.PASSIVE_STAT_LEVELS
	local clampedLevel = math.max(levels[1], math.min(tonumber(level) or levels[1], levels[3]))
	local first, second, third = tonumber(values and values[1]) or 0, tonumber(values and values[2]) or 0, tonumber(values and values[3]) or 0
	if clampedLevel <= levels[2] then
		return math.floor(first + (second - first) * (clampedLevel - levels[1]) / (levels[2] - levels[1]))
	end
	return math.floor(second + (third - second) * (clampedLevel - levels[2]) / (levels[3] - levels[2]))
end

local function splitWarrantBlocks(text)
	local blocks, block = { }, { }
	for line in (text.."\n"):gmatch("(.-)\n") do
		line = line:match("^%s*(.-)%s*$")
		if line:match("^%-+$") then
			if #block > 0 then table.insert(blocks, block) end
			block = { }
		elseif line ~= "" then
			table.insert(block, line)
		end
	end
	if #block > 0 then table.insert(blocks, block) end
	return blocks
end

local function namedRecords(records, ids, name)
	local matches = { }
	if ids then
		for _, id in ipairs(ids) do
			local record = records[id]
			if record and record.name == name then table.insert(matches, id) end
		end
	else
		for id, record in pairs(records or { }) do
			if record.name == name then table.insert(matches, id) end
		end
		table.sort(matches)
	end
	return matches
end

function MercenaryTools.importWarrant(text, mercenaryData)
	if type(text) ~= "string" or text:match("^%s*$") then
		return nil, "Paste a Mercenary Warrant item text"
	elseif #text > MAX_WARRANT_BYTES then
		return nil, "Mercenary Warrant text exceeds 256 KiB"
	elseif not mercenaryData or not mercenaryData.builds or not mercenaryData.skills or not mercenaryData.supports then
		return nil, "Mercenary data is unavailable"
	end

	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	local blocks = splitWarrantBlocks(text)
	local hasWarrant, buildName, foundAreaLevel = false, nil, nil
	for _, block in ipairs(blocks) do
		for _, line in ipairs(block) do
			hasWarrant = hasWarrant or line == "Mercenary Warrant"
			local value = line:match("^Build:%s*(.-)%s*$")
			if value then
				buildName = value
			end
			value = line:match("^Mercenary Level:%s*(%d+)%s*$")
			if value then
				foundAreaLevel = tonumber(value)
			end
		end
	end
	if not hasWarrant then return nil, "Text is not a Mercenary Warrant" end
	if not buildName then return nil, "Mercenary Warrant is missing its Build line" end
	if not foundAreaLevel then return nil, "Mercenary Warrant is missing its Mercenary Level line" end
	if foundAreaLevel < 1 or foundAreaLevel > 100 then
		return nil, "Mercenary Level must be an integer between 1 and 100"
	end

	local buildIds = namedRecords(mercenaryData.builds, mercenaryData.buildOrder, buildName)
	if #buildIds == 0 then
		return nil, "Unknown Mercenary build: "..buildName
	elseif #buildIds > 1 then
		return nil, "Ambiguous Mercenary build: "..buildName
	end
	local build = mercenaryData.builds[buildIds[1]]
	local importedSkills, startedSkills = { }, false
	local sawBuildLine, sawLevelLine = false, false
	for _, block in ipairs(blocks) do
		local firstLine = block[1]
		if firstLine and firstLine:match("^Right click this item") then break end

		local hasMetadataLine = false
		for _, line in ipairs(block) do
			if line:match("^Build:") then
				sawBuildLine = true
				hasMetadataLine = true
			end
			if line:match("^Mercenary Level:") then
				sawLevelLine = true
				hasMetadataLine = true
			end
		end
		local metadataReady = sawBuildLine and sawLevelLine
		if metadataReady and not hasMetadataLine then
			local skillIds = namedRecords(mercenaryData.skills, build.skillIds, firstLine)
			if #skillIds == 0 then
				return nil, "Unknown Mercenary skill for "..buildName..": "..tostring(firstLine)
			elseif #skillIds > 1 then
				return nil, "Ambiguous Mercenary skill for "..buildName..": "..firstLine
			elseif #importedSkills >= MAX_SKILLS then
				return nil, "A Mercenary Warrant cannot contain more than 6 skills"
			end

			local skillId = skillIds[1]
			local skill = mercenaryData.skills[skillId]
			local importedSkill = {
				id = skillId,
				enabled = true,
				includeInFullDPS = false,
				count = 1,
				supports = { },
			}
			local seenSupports, seenFamilies = { }, { }
			for lineIndex = 2, #block do
				local supportName, tierText = block[lineIndex]:match("^(.+)%s+%(%s*Tier:%s*(%d+)%s*%)$")
				if not supportName then
					return nil, "Invalid support line for "..skill.name..": "..block[lineIndex]
				end
				local tier = tonumber(tierText)
				local supportIds = { }
				for _, supportId in ipairs(skill.possibleSupportIds or { }) do
					local support = mercenaryData.supports[supportId]
					if support and support.name == supportName and support.variant == tier then
						table.insert(supportIds, supportId)
					end
				end
				if #supportIds == 0 then
					return nil, "Support "..supportName.." (Tier: "..tier..") is not valid for "..skill.name
				elseif #supportIds > 1 then
					return nil, "Ambiguous support "..supportName.." (Tier: "..tier..") for "..skill.name
				end
				local supportId = supportIds[1]
				local support = mercenaryData.supports[supportId]
				if seenSupports[supportId] then
					return nil, "Duplicate support "..supportName.." on "..skill.name
				elseif support.familyId and seenFamilies[support.familyId] then
					return nil, "Duplicate support family "..support.familyId.." on "..skill.name
				end
				seenSupports[supportId] = true
				if support.familyId then seenFamilies[support.familyId] = true end
				table.insert(importedSkill.supports, { id = supportId, tier = tier })
			end
			table.insert(importedSkills, importedSkill)
			startedSkills = true
		elseif startedSkills and firstLine then
			return nil, "Unexpected text after Mercenary skills: "..firstLine
		end
	end
	if #importedSkills == 0 then return nil, "Mercenary Warrant contains no recognized skills" end

	local profile = {
		classId = build.classId,
		buildId = build.id,
		foundAreaLevel = foundAreaLevel,
		importedWarrant = true,
		mainSkillId = importedSkills[1].id,
		skills = importedSkills,
	}
	local errors = MercenaryTools.validateProfile(profile, mercenaryData)
	if #errors > 0 then return nil, table.concat(errors, "; ") end
	return profile
end

function MercenaryTools.validateProfile(profile, mercenaryData)
	local errors = { }
	local build = profile and mercenaryData and mercenaryData.builds[profile.buildId]
	if not build then
		table.insert(errors, "Select a Mercenary class and build")
		return errors
	end
	local foundAreaLevel = tonumber(profile.foundAreaLevel)
	if not foundAreaLevel or foundAreaLevel % 1 ~= 0 or foundAreaLevel < 1 or foundAreaLevel > 100 then
		table.insert(errors, "Found-area level must be an integer between 1 and 100")
	end
	if #(profile.skills or { }) > MAX_SKILLS then
		table.insert(errors, "A Mercenary cannot have more than 6 inherent skills")
	end
	local seenSkills, enabledSkillsById = { }, { }
	local poolCounts = { }
	local enabledSkills = 0
	for _, selected in ipairs(profile.skills or { }) do
		if selected.count ~= nil and (type(selected.count) ~= "number" or selected.count % 1 ~= 0 or selected.count < 1 or selected.count > 99) then
			table.insert(errors, "Full DPS count for "..tostring(selected.id).." must be an integer from 1 to 99")
		end
		if selected.enabled ~= false and selected.id then
			enabledSkills = enabledSkills + 1
			enabledSkillsById[selected.id] = true
		end
		local skill = mercenaryData.skills[selected.id]
		if not skill or not contains(build.skillIds, selected.id) then
			table.insert(errors, "Invalid skill for selected build: "..tostring(selected.id))
		elseif seenSkills[selected.id] then
			table.insert(errors, "Duplicate skill: "..selected.id)
		else
			seenSkills[selected.id] = true
		end
		for poolIndex, pool in ipairs(build.skillPools or { }) do
			if contains(pool.skillIds, selected.id) then
				poolCounts[poolIndex] = (poolCounts[poolIndex] or 0) + 1
				break
			end
		end
		local maxSupports = skill and supportLimit(mercenaryData, skill)
		if maxSupports and #(selected.supports or { }) > maxSupports then
			table.insert(errors, "Skill "..tostring(selected.id).." has more than "..maxSupports.." supports")
		end
		local seenSupports, seenFamilies = { }, { }
		for _, selectedSupport in ipairs(selected.supports or { }) do
			local supportId = selectedSupport and selectedSupport.id
			local support = mercenaryData.supports[supportId]
			if not support or not skill or not contains(skill.possibleSupportIds, supportId) then
				table.insert(errors, "Invalid support for skill "..tostring(selected.id)..": "..tostring(supportId))
			elseif selectedSupport.tier ~= support.variant then
				table.insert(errors, "Invalid tier for support "..selectedSupport.id)
			elseif seenSupports[supportId] then
				table.insert(errors, "Duplicate support "..selectedSupport.id.." on skill "..tostring(selected.id))
			elseif support.familyId and seenFamilies[support.familyId] then
				table.insert(errors, "Duplicate support family "..support.familyId.." on skill "..tostring(selected.id))
			end
			if supportId then seenSupports[supportId] = true end
			if support and support.familyId then seenFamilies[support.familyId] = true end
		end
	end
	-- Warrant text contains the authoritative complete roster. The exported pool
	-- maximums describe spawn selection, so they do not constrain an imported Warrant.
	if not profile.importedWarrant then
		for poolIndex, pool in ipairs(build.skillPools or { }) do
			if pool.countMax and (poolCounts[poolIndex] or 0) > pool.countMax then
				table.insert(errors, "Skill pool "..poolIndex.." allows at most "..pool.countMax.." skills")
			end
		end
	end
	if #(profile.skills or { }) == 0 then
		table.insert(errors, "Select at least one Mercenary skill")
	elseif enabledSkills == 0 then
		table.insert(errors, "Enable at least one Mercenary skill")
	elseif not profile.mainSkillId then
		table.insert(errors, "Select a Mercenary skill for Calcs")
	elseif not seenSkills[profile.mainSkillId] then
		table.insert(errors, "Selected Calcs skill is not configured")
	elseif not enabledSkillsById[profile.mainSkillId] then
		table.insert(errors, "Selected Calcs skill is disabled")
	end
	return errors
end

return MercenaryTools
