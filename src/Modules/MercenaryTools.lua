local dkjson = require("dkjson")

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
local MAX_SUPPORTS = 5
local contains

local function supportLimit(mercenaryData, skill)
	local count = skill and mercenaryData.supportCounts and mercenaryData.supportCounts[skill.supportCountId]
	return count and count.maximum or MAX_SUPPORTS
end

local function hashMatches(index, hash)
	return index[tostring(hash)] or { }
end

local function resolveUnique(index, hash, kind, allowed)
	if type(hash) ~= "number" and type(hash) ~= "string" then
		return nil, kind.." hash is missing"
	end
	local matches = { }
	for _, id in ipairs(hashMatches(index, hash)) do
		if not allowed or contains(allowed, id) then table.insert(matches, id) end
	end
	if #matches == 0 then
		return nil, "Unknown "..kind.." hash: "..tostring(hash)
	elseif #matches > 1 then
		return nil, "Ambiguous "..kind.." hash: "..tostring(hash)
	end
	return matches[1]
end

local function resolveSupport(mercenaryData, hash, tier, allowed)
	if type(hash) ~= "number" and type(hash) ~= "string" then
		return nil, "Support hash is missing"
	end
	local matches = hashMatches(mercenaryData.supportsByHash, hash)
	if #matches == 0 then
		return nil, "Unknown support hash: "..tostring(hash)
	end
	local tierMatches = { }
	for _, supportId in ipairs(matches) do
		if contains(allowed, supportId) and mercenaryData.supports[supportId].variant == tier then
			table.insert(tierMatches, supportId)
		end
	end
	if #tierMatches == 0 then
		return nil, "Support hash "..tostring(hash).." does not have tier "..tostring(tier)
	elseif #tierMatches > 1 then
		return nil, "Ambiguous support hash/tier: "..tostring(hash).."/"..tostring(tier)
	end
	return tierMatches[1]
end

contains = function(values, wanted)
	for _, value in ipairs(values or { }) do
		if value == wanted then
			return true
		end
	end
	return false
end

function MercenaryTools.effectiveLevel(foundAreaLevel, currentAreaLevel)
	return math.max(tonumber(foundAreaLevel) or 1, math.min(tonumber(currentAreaLevel) or 1, 68))
end

function MercenaryTools.requiredFoundAreaLevel(requiredLevel)
	return math.ceil((tonumber(requiredLevel) or 0) * 0.7)
end

function MercenaryTools.monsterLifeTable(data, scaling)
	return scaling == "AltLife1" and data.monsterLifeTable2 or scaling == "AltLife2" and data.monsterLifeTable3 or data.monsterAllyLifeTable
end

function MercenaryTools.passiveStatValue(values, level)
	local scaledLevel = math.max(0, math.min((tonumber(level) or 1) - 1, 100))
	local first, second, third = tonumber(values and values[1]) or 0, tonumber(values and values[2]) or 0, tonumber(values and values[3]) or 0
	if scaledLevel <= 50 then
		return math.floor(first + (second - first) * scaledLevel / 50)
	end
	return math.floor(second + (third - second) * (scaledLevel - 50) / 50)
end

function MercenaryTools.importWarrant(jsonText, mercenaryData, classId)
	if type(jsonText) ~= "string" or jsonText == "" then
		return nil, "Paste a Warrant item JSON object"
	elseif #jsonText > MAX_WARRANT_BYTES then
		return nil, "Warrant JSON exceeds 256 KiB"
	elseif not mercenaryData or not mercenaryData.classes or not mercenaryData.classes[classId] then
		return nil, "Select the Mercenary class before importing a Warrant"
	end

	local decoded, decodePosition, decodeError = dkjson.decode(jsonText)
	if not decoded then
		return nil, "Invalid Warrant JSON: "..tostring(decodeError)
	elseif jsonText:sub(decodePosition):find("%S") then
		return nil, "Invalid Warrant JSON: trailing data"
	end
	local item = decoded.item or decoded
	if type(item) ~= "table" or type(item.mercenarySkills) ~= "table" then
		return nil, "Warrant JSON has no Item.mercenarySkills array"
	elseif #item.mercenarySkills == 0 or #item.mercenarySkills > MAX_SKILLS then
		return nil, "A Warrant must contain between 1 and 6 Mercenary skills"
	end

	local class = mercenaryData.classes[classId]
	local result = { skills = { } }
	local usedSkills = { }
	for skillIndex, apiSkill in ipairs(item.mercenarySkills) do
		if type(apiSkill) ~= "table" then
			return nil, "Mercenary skill "..skillIndex.." is not an object"
		end
		local skillId, skillError = resolveUnique(mercenaryData.skillsByHash, apiSkill.hash, "skill", class.skillIds)
		if not skillId then
			return nil, skillError
		elseif not contains(class.skillIds, skillId) then
			return nil, "Skill "..skillId.." is not valid for class "..class.id
		elseif usedSkills[skillId] then
			return nil, "Duplicate Mercenary skill: "..skillId
		end
		usedSkills[skillId] = true

		local apiSupports = apiSkill.supports or { }
		local skill = mercenaryData.skills[skillId]
		local maxSupports = supportLimit(mercenaryData, skill)
		if type(apiSupports) ~= "table" or #apiSupports > maxSupports then
			return nil, "Skill "..skillId.." has more than "..maxSupports.." supports"
		end
		local importedSkill = {
			id = skillId,
			enabled = true,
			includeInFullDPS = false,
			count = 1,
			supports = { },
		}
		local usedSupports, usedFamilies = { }, { }
		for supportIndex, apiSupport in ipairs(apiSupports) do
			if type(apiSupport) ~= "table" then
				return nil, "Support "..supportIndex.." for "..skillId.." is not an object"
			end
			local tier = tonumber(apiSupport.tier)
			if not tier or tier % 1 ~= 0 or tier < 1 then
				return nil, "Invalid support tier on skill "..skillId
			end
			local supportId, supportError = resolveSupport(mercenaryData, apiSupport.hash, tier, skill.possibleSupportIds)
			if not supportId then
				return nil, supportError
			end
			local support = mercenaryData.supports[supportId]
			if not contains(skill.possibleSupportIds, supportId) then
				return nil, "Support "..supportId.." is not valid for skill "..skillId
			elseif usedSupports[supportId] then
				return nil, "Duplicate support "..supportId.." on skill "..skillId
			elseif support.familyId and usedFamilies[support.familyId] then
				return nil, "Duplicate support family "..support.familyId.." on skill "..skillId
			end
			usedSupports[supportId] = true
			if support.familyId then usedFamilies[support.familyId] = true end
			table.insert(importedSkill.supports, { id = supportId, tier = tier })
		end
		table.insert(result.skills, importedSkill)
	end
	return result
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
		if selected.enabled ~= false then
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
		local maxSupports = supportLimit(mercenaryData, skill)
		if #(selected.supports or { }) > maxSupports then
			table.insert(errors, "Skill "..tostring(selected.id).." has more than "..maxSupports.." supports")
		end
		local seenSupports, seenFamilies = { }, { }
		for _, selectedSupport in ipairs(selected.supports or { }) do
			local support = mercenaryData.supports[selectedSupport.id]
			if not support or not skill or not contains(skill.possibleSupportIds, selectedSupport.id) then
				table.insert(errors, "Invalid support for skill "..tostring(selected.id)..": "..tostring(selectedSupport.id))
			elseif selectedSupport.tier ~= support.variant then
				table.insert(errors, "Invalid tier for support "..selectedSupport.id)
			elseif seenSupports[selectedSupport.id] then
				table.insert(errors, "Duplicate support "..selectedSupport.id.." on skill "..tostring(selected.id))
			elseif support.familyId and seenFamilies[support.familyId] then
				table.insert(errors, "Duplicate support family "..support.familyId.." on skill "..tostring(selected.id))
			end
			seenSupports[selectedSupport.id] = true
			if support and support.familyId then seenFamilies[support.familyId] = true end
		end
	end
	for poolIndex, pool in ipairs(build.skillPools or { }) do
		if pool.countMax and (poolCounts[poolIndex] or 0) > pool.countMax then
			table.insert(errors, "Skill pool "..poolIndex.." allows at most "..pool.countMax.." skills")
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

function MercenaryTools.copyImportedSkills(imported)
	local result = { }
	for _, skill in ipairs(imported.skills or { }) do
		local copy = {
			id = skill.id,
			enabled = skill.enabled,
			includeInFullDPS = skill.includeInFullDPS,
			count = skill.count,
			supports = { },
		}
		for _, support in ipairs(skill.supports or { }) do
			table.insert(copy.supports, { id = support.id, tier = support.tier })
		end
		table.insert(result, copy)
	end
	return result
end

return MercenaryTools
