local skillTypeMap = { }
for row in dat("ActiveSkillType"):Rows() do
	table.insert(skillTypeMap, row.Id)
end

-- This is here to fix name collisions like in the case of Barrage
local fullNameGems = {
	["Metadata/Items/Gems/SupportGemBarrage"] = true,
}

local function mapAST(ast)
	return "SkillType."..(skillTypeMap[ast._rowIndex] or ("Unknown"..ast._rowIndex))
end

local weaponClassMap = {
	["Claw"] = "Claw",
	["Dagger"] = "Dagger",
	["Wand"] = "Wand",
	["One Hand Sword"] = "One Handed Sword",
	["Thrusting One Hand Sword"] = "Thrusting One Handed Sword",
	["One Hand Axe"] = "One Handed Axe",
	["One Hand Mace"] = "One Handed Mace",
	["Bow"] = "Bow",
	["FishingRod"] = "Fishing Rod",
	["Staff"] = "Staff",
	["Two Hand Sword"] = "Two Handed Sword",
	["Two Hand Axe"] = "Two Handed Axe",
	["Two Hand Mace"] = "Two Handed Mace",
	["Sceptre"] = "Sceptre",
	["Unarmed"] = "None",
}

local skillStatScope = { }
do
	local text = convertUTF16to8(getFile("Metadata/StatDescriptions/skillpopup_stat_filters.txt"))
	for skillName, scope in text:gmatch('([%w_]+) "Metadata/StatDescriptions/([%w_]+)%.txt"') do
		skillStatScope[skillName] = scope
	end
	for skillName, copyFromSkill in text:gmatch('copy ([%w_]+) ([%w_]+)') do
		skillStatScope[skillName] = skillStatScope[copyFromSkill]
	end
end

local function cleanAndSplit(str) -- Same as in Flavour Text exporter.
	-- Normalize newlines
	str = str:gsub("\r\n", "\n")

	local lines = {}
	for line in str:gmatch("[^\n]+") do
		line = line:match("^%s*(.-)%s*$") -- trim each line
		if line ~= "" then
			-- Escape quotes
			line = line:gsub('"', '\\"')
			table.insert(lines, line)
		end
	end

	return lines
end
local gems = { }
local trueGemNames = { }

local directiveTable = { }

-- #noGem
-- Disables the gem component of the next skill
directiveTable.noGem = function(state, args, out)
	state.noGem = true
end

-- #addSkillTypes <flag>[ <flag>[...]]
-- skill types to be added to the skillTypes flags for this active skill
directiveTable.addSkillTypes = function(state, args, out)
	state.addSkillTypes = {}
	for flag in args:gmatch("%a+") do
		table.insert(state.addSkillTypes, flag)
	end
end

local mercenarySkills

local function mercenaryLevelRows(effectLevels, statLevels)
	local rows = { }
	if #effectLevels == 1 then
		for _, stat in ipairs(statLevels) do table.insert(rows, { effect = effectLevels[1], stats = stat }) end
	elseif #statLevels == 1 then
		for _, effect in ipairs(effectLevels) do table.insert(rows, { effect = effect, stats = statLevels[1] }) end
	else
		local effects = { }
		for _, effect in ipairs(effectLevels) do effects[effect.Level] = effect end
		for _, stat in ipairs(statLevels) do
			if effects[stat.GemLevel] then table.insert(rows, { effect = effects[stat.GemLevel], stats = stat }) end
		end
	end
	return rows
end

local function skillLevelRow(effectLevels, statLevels, mercenaryRows, index)
	if mercenaryRows then return mercenaryRows[index].effect, mercenaryRows[index].stats end
	return effectLevels[index] or effectLevels[1], statLevels[index] or statLevels[1]
end

-- #skill <GrantedEffectId> [<Display name>]
-- Initialises the skill data and emits the skill header
directiveTable.skill = function(state, args, out)
	local isMercenary = state.mercenary
	local grantedId, displayName = args:match("(%w+) (.+)")
	if not grantedId then
		grantedId = args
		displayName = args
	end
	out:write('skills["', grantedId, '"] = {\n')
	local granted = dat("GrantedEffects"):GetRow("Id", grantedId)
	if not granted then
		ConPrintf('Unknown GE: "'..grantedId..'"')
		return
	end
	local gemEffect = dat("GemEffects"):GetRow("GrantedEffect", granted)
	local secondaryEffect
	if not gemEffect then
		gemEffect = dat("GemEffects"):GetRow("GrantedEffect2", granted)
		if gemEffect then 
			secondaryEffect = true
		end
	end
	local skillGem
	if gemEffect then
		for gem in dat("SkillGems"):Rows() do
			for _, variant in ipairs(gem.GemVariants) do
				if gemEffect.Id == variant.Id then
					skillGem = gem
					local trueGemNameObj = dat("GemEffects"):GetRow("Id", gemEffect.Id)
					if trueGemNameObj.Name ~= "" then
						trueGemNames[gemEffect.Id] = trueGemNameObj.Name
					end
					break
				end
			end
			if skillGem then break end
		end
	end
	local skill = { }
	state.skill = skill
	if skillGem and not state.noGem then
		gems[gemEffect.Id] = true
		if granted.IsSupport then
			out:write('\tname = "', fullNameGems[skillGem.BaseItemType.Id] and skillGem.BaseItemType.Name or skillGem.BaseItemType.Name:gsub(" Support",""), '",\n')
			if #gemEffect.Description > 0 then
				out:write('\tdescription = "', escapeGGGString(gemEffect.Description:gsub('"','\\"'):gsub('\r',''):gsub('\n','\\n')), '",\n')
			end
		else
			out:write('\tname = "', secondaryEffect and granted.ActiveSkill.DisplayName or trueGemNames[gemEffect.Id] or granted.ActiveSkill.DisplayName, '",\n')
			-- Hybrid gems (e.g. Vaal gems) use the display name of the active skill e.g. Vaal Summon Skeletons of Sorcery
			out:write('\tbaseTypeName = "', granted.ActiveSkill.DisplayName, '",\n')
		end
	else
		if displayName == args and not granted.IsSupport then
			displayName = gemEffect and trueGemNames[gemEffect.Id] or granted.ActiveSkill.DisplayName
		end
		out:write('\tname = "', displayName, '",\n')
		out:write('\thidden = true,\n')
	end
	if state.mercenary then
		out:write('\tmercenary = true,\n')
		if state.mercenaryBaseSkillId then
			out:write('\tinheritedFrom = "', state.mercenaryBaseSkillId, '",\n')
		end
	end
	state.mercenary = nil
	state.mercenaryBaseSkillId = nil
	if skillGem and skillGem.BaseItemType and skillGem.BaseItemType.FlavourTextKey then
		out:write('\tflavourText = {')
		for _, line in ipairs(cleanAndSplit(skillGem.BaseItemType.FlavourTextKey.Text)) do
			out:write('"', line, '", ')
		end
		out:write('},\n')
	end
	state.noGem = false
	skill.baseFlags = { }
	local modMap = { }
	skill.mods = { }
	skill.levels = { }
	local statMap = { }
	skill.stats = { }
	skill.CannotGrantToMinion = { }
	skill.isMercenary = isMercenary
	skill.constantStats = { }
	skill.addSkillTypes = state.addSkillTypes
	state.addSkillTypes = nil
	out:write('\tcolor = ', granted.Attribute, ',\n')
	if granted.GrantedEffectStatSets.BaseEffectiveness ~= 1 then
		out:write('\tbaseEffectiveness = ', granted.GrantedEffectStatSets.BaseEffectiveness, ',\n')
	end
	if granted.GrantedEffectStatSets.IncrementalEffectiveness ~= 0 then
		out:write('\tincrementalEffectiveness = ', granted.GrantedEffectStatSets.IncrementalEffectiveness, ',\n')
	end
	if granted.IsSupport then
		skill.isSupport = true
		out:write('\tsupport = true,\n')
		out:write('\trequireSkillTypes = { ')
		for _, type in ipairs(granted.SupportTypes) do
			out:write(mapAST(type), ', ')
		end
		out:write('},\n')
		out:write('\taddSkillTypes = { ')
		skill.isTrigger = false
		for _, type in ipairs(granted.AddTypes) do
			local typeString = mapAST(type)
			if typeString == "SkillType.Triggered" then
				skill.isTrigger = true
			end
			out:write(typeString, ', ')
		end
		out:write('},\n')
		out:write('\texcludeSkillTypes = { ')
		for _, type in ipairs(granted.ExcludeTypes) do
			out:write(mapAST(type), ', ')
		end
		out:write('},\n')
		if skill.isTrigger then
			out:write('\tisTrigger = true,\n')
		end
		if granted.SupportGemsOnly then
			out:write('\tsupportGemsOnly = true,\n')
		end
		if granted.IgnoreMinionTypes then
			out:write('\tignoreMinionTypes = true,\n')
		end
		if granted.PlusVersionOf then
			out:write('\tplusVersionOf = "', granted.PlusVersionOf.Id, '",\n')
		end
		local weaponTypes = { }
		for _, class in ipairs(granted.WeaponRestrictions) do
			if weaponClassMap[class.Id] then
				weaponTypes[weaponClassMap[class.Id]] = true
			end
		end
		if next(weaponTypes) then
			out:write('\tweaponTypes = {\n')
			for type in pairsSortByKey(weaponTypes) do
				out:write('\t\t["', type, '"] = true,\n')
			end
			out:write('\t},\n')
		end
		out:write('\tstatDescriptionScope = "gem_stat_descriptions",\n')
	else
		if #granted.ActiveSkill.Description > 0 then
			out:write('\tdescription = "', escapeGGGString(granted.ActiveSkill.Description:gsub('"','\\"'):gsub('\r',''):gsub('\n','\\n')), '",\n')
		end
		out:write('\tskillTypes = { ')
		for _, type in ipairs(granted.ActiveSkill.SkillTypes) do
			out:write('[', mapAST(type), '] = true, ')
		end
		if skill.addSkillTypes then
			for _, type in ipairs(skill.addSkillTypes) do
				out:write('[SkillType.', type , '] = true, ')
			end
		end
		out:write('},\n')
		if granted.ActiveSkill.MinionSkillTypes[1] then
			out:write('\tminionSkillTypes = { ')
			for _, type in ipairs(granted.ActiveSkill.MinionSkillTypes) do
				out:write('[', mapAST(type), '] = true, ')
			end
			out:write('},\n')
		end
		local weaponTypes = { }
		for _, class in ipairs(granted.ActiveSkill.WeaponRestrictions) do
			if weaponClassMap[class.Id] then
				weaponTypes[weaponClassMap[class.Id]] = true
			end
		end
		if next(weaponTypes) then
			out:write('\tweaponTypes = {\n')
			for type in pairsSortByKey(weaponTypes) do
				out:write('\t\t["', type, '"] = true,\n')
			end
			out:write('\t},\n')
		end
		out:write('\tstatDescriptionScope = "', skillStatScope[granted.ActiveSkill.Id] or "skill_stat_descriptions", '",\n')
		if granted.ActiveSkill.SkillTotem <= 21 then
			out:write('\tskillTotemId = ', granted.ActiveSkill.SkillTotem, ',\n')
		end
		out:write('\tcastTime = ', granted.CastTime / 1000, ',\n')
		if granted.CannotBeSupported then
			out:write('\tcannotBeSupported = true,\n')
		end
	end
	local statsPerLevel = dat("GrantedEffectStatSetsPerLevel"):GetRowList("GrantedEffectStatSets", granted.GrantedEffectStatSets)
	local statMapOrder = {}
	local perLevel = dat("GrantedEffectsPerLevel"):GetRowList("GrantedEffect", granted)
	if not isMercenary and #perLevel ~= #statsPerLevel and #perLevel > 1 and #statsPerLevel > 1 then
		ConPrintf("UNKNOWN CASE of Level to Stat rows for '" .. granted.Id .. "'")
	end
	local mercenaryRows = isMercenary and mercenaryLevelRows(perLevel, statsPerLevel)
	for indx = 1, mercenaryRows and #mercenaryRows or math.max(#perLevel, #statsPerLevel) do
		local levelRow, statRow = skillLevelRow(perLevel, statsPerLevel, mercenaryRows, indx)
		local level = { extra = { }, statInterpolation = { }, cost = { } }
		level.level = #perLevel == 1 and statRow.GemLevel or levelRow.Level
		level.extra.levelRequirement = #perLevel == 1 and statRow.PlayerLevelReq or levelRow.PlayerLevelReq
		for i, cost in ipairs(levelRow.CostTypes) do
			level.cost[cost["Resource"]] = levelRow.CostAmounts[i]
		end
		if levelRow.ManaReservationFlat ~= 0 then
			level.extra.manaReservationFlat = levelRow.ManaReservationFlat
		end
		if levelRow.ManaReservationPercent ~= 0 then
			level.extra.manaReservationPercent = levelRow.ManaReservationPercent / 100
		end
		if levelRow.LifeReservationFlat ~= 0 then
			level.extra.lifeReservationFlat = levelRow.LifeReservationFlat
		end
		if levelRow.LifeReservationPercent ~= 0 then
			level.extra.lifeReservationPercent = levelRow.LifeReservationPercent / 100
		end
		if levelRow.CostMultiplier ~= 100 then
			level.extra.manaMultiplier = levelRow.CostMultiplier - 100
		end
		if levelRow.AttackSpeedMultiplier and levelRow.AttackSpeedMultiplier ~= 0 then
			level.extra.attackSpeedMultiplier = levelRow.AttackSpeedMultiplier
		end
		if levelRow.AttackTime ~= 0 then
			level.extra.attackTime = levelRow.AttackTime
		end
		if levelRow.Cooldown and levelRow.Cooldown ~= 0 then
			level.extra.cooldown = levelRow.Cooldown / 1000
		end
		if levelRow.PvPDamageMultiplier ~= 0 then
			level.extra.PvPDamageMultiplier = levelRow.PvPDamageMultiplier
		end
		if levelRow.StoredUses ~= 0 then
			level.extra.storedUses = levelRow.StoredUses
		end
		if levelRow.VaalSouls ~= 0 then
			level.cost.Soul = levelRow.VaalSouls
		end
		if levelRow.VaalStoredUses ~= 0 then
			level.extra.vaalStoredUses = levelRow.VaalStoredUses
		end
		if levelRow.SoulGainPreventionDuration ~= 0 then
			level.extra.soulPreventionDuration = levelRow.SoulGainPreventionDuration / 1000
		end
		-- stat based level info
		if statRow.DamageEffectiveness ~= 0 then
			level.extra.damageEffectiveness = statRow.DamageEffectiveness / 10000 + 1
		end
		if statRow.AttackCritChance ~= 0 then
			level.extra.critChance = statRow.AttackCritChance / 100
		end
		if statRow.OffhandCritChance ~= 0 then
			level.extra.critChance = statRow.OffhandCritChance / 100
		end
		if statRow.BaseMultiplier and statRow.BaseMultiplier ~= 0 then
			level.extra.baseMultiplier = statRow.BaseMultiplier / 10000 + 1
		end
		level.statInterpolation = isMercenary and copyTable(statRow.StatInterpolations, true) or statRow.StatInterpolations
		local resolveInterpolation = false
		local injectConstantValuesIntoEachLevel = false
		local statMapOrderIndex = 1
		for i, stat in ipairs(statRow.FloatStats) do
			if not statMap[stat.Id] or indx == 1 then
				statMap[stat.Id] = #skill.stats + 1
				table.insert(skill.stats, { id = stat.Id })
				if indx == 1 then
					table.insert(statMapOrder, stat.Id)
					if stat.CannotGrantToMinion then
						table.insert(skill.CannotGrantToMinion, stat.Id)
					end
				else
					print(displayName .. ": stat missing from earlier levels: ".. stat.Id)
				end
			elseif statMapOrder[statMapOrderIndex] ~= stat.Id then
				-- add missing stats
				while statMapOrderIndex < #statMapOrder and statMapOrder[statMapOrderIndex] ~= stat.Id do
					table.insert(level, 0)
					if #level.statInterpolation < #statMapOrder then
						table.insert(level.statInterpolation, statMapOrderIndex, "0")
					end
					statMapOrderIndex = statMapOrderIndex + 1
				end
			end
			statMapOrderIndex = statMapOrderIndex + 1
			if resolveInterpolation then
				table.insert(level, statRow.BaseResolvedValues[i])
				level.statInterpolation[statMapOrderIndex] = 1
			else
				table.insert(level, statRow.FloatStatsValues[i] / math.max(statRow.InterpolationBases[i].Value, 0.00001) )
			end
		end
		if injectConstantValuesIntoEachLevel then
			for i, stat in ipairs(granted.GrantedEffectStatSets.ConstantStats) do
				if not statMap[stat.Id] then
					statMap[stat.Id] = #skill.stats + #skill.constantStats + 1
					table.insert(skill.stats, { id = stat.Id })
					if indx == 1 then
						table.insert(statMapOrder, stat.Id)
					else
						print(displayName .. ": stat missing from earlier levels: ".. stat.Id)
					end
				elseif statMapOrder[statMapOrderIndex] ~= stat.Id then
					-- add missing stats
					while statMapOrderIndex < #statMapOrder and statMapOrder[statMapOrderIndex] ~= stat.Id do
						table.insert(level, 0)
						if #level.statInterpolation < #statMapOrder then
							table.insert(level.statInterpolation, statMapOrderIndex, "0")
						end
						statMapOrderIndex = statMapOrderIndex + 1
					end
				end
				statMapOrderIndex = statMapOrderIndex + 1
				table.insert(level, granted.GrantedEffectStatSets.ConstantStatsValues[i])
				table.insert(level.statInterpolation, #statRow.FloatStats + 1, 1)
			end
		end
		for i, stat in ipairs(statRow.AdditionalStats) do
			if not statMap[stat.Id] then
				statMap[stat.Id] = #skill.stats + 1
				table.insert(skill.stats, { id = stat.Id })
				if indx == 1 then
					table.insert(statMapOrder, stat.Id)
					if stat.CannotGrantToMinion then
						table.insert(skill.CannotGrantToMinion, stat.Id)
					end
				else
					print(displayName .. ": stat missing from earlier levels: ".. stat.Id)
				end
			elseif statMapOrder[statMapOrderIndex] ~= stat.Id then
				-- add missing stats
				while statMapOrderIndex < #statMapOrder and statMapOrder[statMapOrderIndex] ~= stat.Id do
					table.insert(level, 0)
					if #level.statInterpolation < #statMapOrder then
						table.insert(level.statInterpolation, statMapOrderIndex, "0")
					end
					statMapOrderIndex = statMapOrderIndex + 1
				end
			end
			statMapOrderIndex = statMapOrderIndex + 1
			table.insert(level, statRow.AdditionalStatsValues[i])
		end
		for i, stat in ipairs(statRow.AdditionalBooleanStats) do
			if not statMap[stat.Id] then
				statMap[stat.Id] = #skill.stats + 1
				table.insert(skill.stats, { id = stat.Id })
				if stat.CannotGrantToMinion then
					table.insert(skill.CannotGrantToMinion, stat.Id)
				end
			end
		end
		table.insert(skill.levels, level)
	end
	for i, stat in ipairs(granted.GrantedEffectStatSets.ImplicitStats) do
		if not statMap[stat.Id] then
			statMap[stat.Id] = #skill.stats + 1
			table.insert(skill.stats, { id = stat.Id })
		end
	end
	for i, stat in ipairs(granted.GrantedEffectStatSets.ConstantStats) do
		table.insert(skill.constantStats, { stat.Id, granted.GrantedEffectStatSets.ConstantStatsValues[i] })
	end
	if isMercenary then skill.CannotGrantToMinion = mercenarySkills.statSets[granted.GrantedEffectStatSets.Id].cannotGrantToMinion end
	if not skill.qualityStats then
		skill.qualityStats = { }
		for i, qualityStatsRow in ipairs(dat("GrantedEffectQualityStats"):GetRowList("GrantedEffect", granted)) do
			for j, stat in ipairs(qualityStatsRow.GrantedStats) do
				if stat.Id ~= "dummy_stat_display_nothing" then
					table.insert(skill.qualityStats, { stat.Id, qualityStatsRow.StatValues[j] / 1000 })
				end
				--ConPrintf("%s %s", granted.ActiveSkill.DisplayName, stat.Id)
			end
		end
	end
end

-- #flags <flag>[ <flag>[...]]
-- Sets the base flags for this active skill
directiveTable.flags = function(state, args, out)
	local skill = state.skill
	for flag in args:gmatch("%a+") do
		table.insert(skill.baseFlags, flag)
	end
end

-- #baseMod <mod definition>
-- Adds a base modifier to the skill
directiveTable.baseMod = function(state, args, out)
	local skill = state.skill
	table.insert(skill.mods, args)
end

-- #mods
-- Emits the skill modifiers
directiveTable.mods = function(state, args, out)
	local skill = state.skill
	if not args:match("noBaseFlags") then
		if not skill.isSupport then
			out:write('\tbaseFlags = {\n')
			for _, flag in ipairs(skill.baseFlags) do
				out:write('\t\t', flag, ' = true,\n')
			end
			out:write('\t},\n')
		end
	end
	if not args:match("noBaseMods") then
		if next(skill.mods) ~= nil then
			out:write('\tbaseMods = {\n')
			for _, mod in ipairs(skill.mods) do
				out:write('\t\t', mod, ',\n')
			end
			out:write('\t},\n')
		end
	end
	if not args:match("noQualityStats") then
		if next(skill.qualityStats) ~= nil then
			out:write('\tqualityStats = {\n')
			for _, stat in ipairs(skill.qualityStats) do
				out:write('\t\t{ "', stat[1], '", ', stat[2], ' },\n')
			end
			out:write('\t},\n')
		end
	end
	if not args:match("noStats") then
		if next(skill.constantStats) ~= nil then
			-- write out constant stats that don't change per level
			out:write('\tconstantStats = {\n')
			for i, stat in ipairs(skill.constantStats) do
				out:write('\t\t{ "', stat[1], '", ', stat[2], ' },\n')
			end
			out:write('\t},\n')
		end
		-- write out per level stats
		out:write('\tstats = {\n')
		for _, stat in ipairs(skill.stats) do
			out:write('\t\t"', stat.id, '",\n')
		end
		out:write('\t},\n')
		if skill.isMercenary or next(skill.CannotGrantToMinion) then
			out:write('\tnotMinionStat = {\n')
			for _, stat in ipairs(skill.CannotGrantToMinion) do
				out:write('\t\t"', stat, '",\n')
			end
			out:write('\t},\n')
		end
	end
	if not args:match("noLevels") then
		out:write('\tlevels = {\n')
		for index, level in ipairs(skill.levels) do
			out:write('\t\t[', level.level, '] = { ')
			for _, statVal in ipairs(level) do
				out:write(tostring(statVal), ', ')
			end
			for k, v in pairsSortByKey(level.extra) do
				out:write(k, ' = ', tostring(v), ', ')
			end
			if next(level.statInterpolation) ~= nil then
				out:write('statInterpolation = { ')
				for _, type in ipairs(level.statInterpolation) do
					out:write(type, ', ')
				end
				out:write('}, ')
			end
			if next(level.cost) ~= nil then
				out:write('cost = { ')
				for k, v in pairsSortByKey(level.cost) do
					out:write(k, ' = ', tostring(v), ', ')
				end
				out:write('}, ')
			end
			out:write('},\n')
		end
		out:write('\t},\n')
	end
	out:write('}')
	state.skill = nil
end

LoadModule("Scripts/mercenaries")
mercenarySkills = LoadModule("../Data/MercenarySkills")
local mercenaryData = LoadModule("../Data/Mercenaries")
local mercenaryExport = LoadModule("MercenaryExport")
for _, name in pairs({"act_str","act_dex","act_int","other","glove","minion","spectre","sup_str","sup_dex","sup_int"}) do
	processTemplateFile(name, "Skills/", "../Data/Skills/", directiveTable)
end

do
	local out = assert(io.open("../Data/Skills/mercenary.lua", "w"))
	out:write("-- This file is automatically generated, do not edit!\n")
	out:write("-- Mercenary skill data (c) Grinding Gear Games\n\nreturn function(skills, mod, flag, skill)\n")
	local emitted = { }
	for _, templateName in ipairs({"act_str","act_dex","act_int","other","glove","minion","spectre","sup_str","sup_dex","sup_int"}) do
		for line in io.lines("Skills/"..templateName..".txt") do
			local id = line:match("^#skill%s+(%S+)")
			if id then
				emitted[id] = true
			end
		end
	end
	local function rankedCandidate(groups)
		if not groups then return end
		for rank, category in ipairs({ "gems", "skills", "supports" }) do
			if #groups[category] > 0 then return { ids = groups[category], rank = rank } end
		end
	end
	local function uniqueCandidate(candidate)
		return candidate and #candidate.ids == 1 and candidate or nil
	end
	local function resolveBaseSkill(effectId, candidates, override)
		local byActiveSkill = rankedCandidate(candidates.activeSkill)
		local byDisplayName = rankedCandidate(candidates.displayName)
		local base = uniqueCandidate(byActiveSkill)
		if uniqueCandidate(byDisplayName) and (not base or byDisplayName.rank < base.rank) then base = byDisplayName end
		if base then return { id = base.ids[1], source = base == byActiveSkill and "activeSkill" or "displayName" } end
		if override then
			assert(emitted[override], "Mercenary base-skill override is not exported: "..effectId.." -> "..override)
			return { id = override, source = "override" }
		end
		assert(not (byActiveSkill or byDisplayName), "Ambiguous Mercenary base skill: "..effectId)
	end
	local flagBySkillType = {
		Attack = "attack",
		Spell = "spell",
		Area = "area",
		Projectile = "projectile",
		Duration = "duration",
		Melee = "melee",
		Minion = "minion",
		Totem = "totem",
		SummonsTotem = "totem",
		Trap = "trap",
		Trapped = "trap",
		Mine = "mine",
		RemoteMined = "mine",
		Movement = "movement",
		Travel = "movement",
		Warcry = "warcry",
		Aura = "aura",
		Curse = "curse",
		Hex = "hex",
		Chaining = "chaining",
		Link = "link",
	}
	local effectNames = { }
	for row in dat("MercenarySkills"):Rows() do
		for _, effect in ipairs({ row.Id, row.EncounterGrantedEffect }) do
			effectNames[effect.Id] = row.Name ~= "" and row.Name or effect.ActiveSkill.DisplayName
		end
	end
	local baseSkillOverrides = {
		-- AtlasEyrieArcherSnipe shares the Mercenary effect's ActiveSkill, but is an
		-- NPC copy; Snipe is the maintained gem implementation.
		SkeletonLargeMapBoneProjectile = "Snipe",
		-- Blood Mortar shares monster_mortar_attack with Herald of Agony's minion
		-- mortar; there is no gem, so inherit the spectre blood-projectile mortar.
		BloodMortarMercenary = "BirdmanBloodProjectileMortar",
		-- These triggered area hits share the generic geometry_attack ActiveSkill
		-- with dozens of spectre slams; keep the previously chosen implementation.
		DeceleratingProjectileMercenaryExplode = "AfflictionMinionPhysSlamCircleBig",
		DonutBladesMercenary = "AfflictionMinionPhysSlamCircleBig",
		TriggeredFireSlamMercenary = "AfflictionMinionPhysSlamCircleBig",
		-- Shares geometry_spell with many spectre spells and has no display name.
		GSRitualChaosPulse = "AtlasExileCrusaderMageguardBombExplodeSpectre",
		-- This explosion also uses geometry_spell; the shared base has no custom mods.
		GSAbyssalTemplarProjectileExplosion = "AtlasExileCrusaderMageguardBombExplodeSpectre",
		-- The shared monster_projectile_spell base has no custom mods.
		MPSAbyssalMercenaryProjectileSpray = "AtlasExilesCrusaderMageguardProjectile",
		-- Shares inspiring_cry with other NPC warcries; there is no gem.
		InspiringCryMercenary = "DropBearSummonedRallyingCry",
		-- Shares offering_of_judgement with the Azmeri fire and chaos pillars.
		OfferingOfJudgementChaosMercenary = "AzmeriGoddessOfferingOfJudgement",
		-- Shares sandstorm with the summoned chaos elemental auras.
		SandstormChaosMercenary = "SandstormChaosElementalSummoned",
	}
	-- Unique ActiveSkill/name matches win. Remaining ties require an explicit
	-- override so a generic shared ActiveSkill cannot silently pick a new base.
	-- Skills with no unique match and no override still fail closed.
	local resolvedByActiveSkill, resolvedByDisplayName, resolvedByOverride, withoutBase = 0, 0, 0, { }
	local wroteSkill = false
	for effectId, metadata in pairsSortByKey(mercenarySkills.grantedEffects) do
		local effect = dat("GrantedEffects"):GetRow("Id", effectId)
		if not emitted[effect.Id] then
				emitted[effect.Id] = true
				local displayName = effectNames[effectId] or metadata.activeSkill.DisplayName
				if displayName == "" then displayName = effectId end
				local resolved = resolveBaseSkill(effectId, metadata.baseSkillCandidates, baseSkillOverrides[effectId])
				if baseSkillOverrides[effect.Id] then
					baseSkillOverrides[effect.Id] = nil
				end
				if resolved then
					if resolved.source == "activeSkill" then
						resolvedByActiveSkill = resolvedByActiveSkill + 1
					elseif resolved.source == "displayName" then
						resolvedByDisplayName = resolvedByDisplayName + 1
					else
						resolvedByOverride = resolvedByOverride + 1
					end
				else
					table.insert(withoutBase, effect.Id)
				end
				if wroteSkill then out:write("\n") end
				wroteSkill = true
				local state = { noGem = true, mercenary = true, mercenaryBaseSkillId = resolved and resolved.id }
				directiveTable.skill(state, effect.Id.." "..displayName, out)
				mercenaryExport.applySkillMetadata(state.skill, metadata, mercenaryData, out)
				local flags = { }
				local summon = mercenaryData.summonedMinions[effectId]
				local buff = summon and mercenaryData.buffs[summon.buffId]
				if buff and isValueInArray(buff.GrantedFlags, "is_raised_spectre") then flags.spectre = true end
				for _, skillType in ipairs(effect.ActiveSkill.SkillTypes) do
					if flagBySkillType[skillType.Id] then
						flags[flagBySkillType[skillType.Id]] = true
					end
				end
				local orderedFlags = { }
				for flagName in pairsSortByKey(flags) do
					table.insert(orderedFlags, flagName)
				end
				directiveTable.flags(state, table.concat(orderedFlags, " "), out)
				directiveTable.mods(state, "", out)
				out:write("\n")
		end
	end
	for effectId in pairs(baseSkillOverrides) do error("Mercenary base-skill override references missing effect: "..effectId) end
	out:write("end\n")
	out:close()
	print(string.format("Mercenary skill bases: %d from a shared ActiveSkill, %d from a shared display name, %d overridden, %d without a base (%s).",
		resolvedByActiveSkill, resolvedByDisplayName, resolvedByOverride, #withoutBase, table.concat(withoutBase, ", ")))
end

local out = io.open("../Data/Gems.lua", "w")
out:write('-- This file is automatically generated, do not edit!\n')
out:write('-- Gem data (c) Grinding Gear Games\n\nreturn {\n')
for skillGem in dat("SkillGems"):Rows() do
	for _, gemEffect in ipairs(skillGem.GemVariants) do
		if gems[gemEffect.Id] then
			gems[gemEffect.Id] = nil -- Some skills have an additional old version that exists in the game files and messes up transfigured gem matching
			out:write('\t["', "Metadata/Items/Gems/SkillGem" .. gemEffect.Id, '"] = {\n')
			out:write('\t\tname = "', fullNameGems[skillGem.BaseItemType.Id] and skillGem.BaseItemType.Name or trueGemNames[gemEffect.Id] or skillGem.BaseItemType.Name:gsub(" Support",""), '",\n')
			-- Hybrid gems (e.g. Vaal gems) use the display name of the active skill e.g. Vaal Summon Skeletons of Sorcery
			if not skillGem.IsSupport then
				out:write('\t\tbaseTypeName = "', gemEffect.GrantedEffect.ActiveSkill.DisplayName, '",\n')
			end
			out:write('\t\tgameId = "', skillGem.BaseItemType.Id, '",\n')
			out:write('\t\tvariantId = "', gemEffect.Id, '",\n')
			out:write('\t\tgrantedEffectId = "', gemEffect.GrantedEffect.Id, '",\n')
			if gemEffect.GrantedEffect2 then
				out:write('\t\tsecondaryGrantedEffectId = "', gemEffect.GrantedEffect2.Id, '",\n')
			end
			if #gemEffect.SecondarySupportName > 0 then
				out:write('\t\tsecondaryEffectName = "', gemEffect.SecondarySupportName, '",\n')
			end
			if skillGem.IsVaalGem then
				out:write('\t\tvaalGem = true,\n')
			end
			local tagNames = { }
			out:write('\t\ttags = {\n')
			for _, tag in ipairs(gemEffect.Tags) do
				tag.Name = escapeGGGString(tag.Name) --Remove the words in brackets e.g. [DurationSkill|Duration] -> Duration
				out:write('\t\t\t', tag.Id, ' = true,\n')
				if #tag.Name > 0 then
					table.insert(tagNames, tag.Name)
				end
			end
			out:write('\t\t},\n')
			out:write('\t\ttagString = "', table.concat(tagNames, ", "), '",\n')
			out:write('\t\treqStr = ', skillGem.Str, ',\n')
			out:write('\t\treqDex = ', skillGem.Dex, ',\n')
			out:write('\t\treqInt = ', skillGem.Int, ',\n')
			local naturalMaxLevel = #dat("ItemExperiencePerLevel"):GetRowList("ItemExperienceType", skillGem.GemLevelProgression)
			out:write('\t\tnaturalMaxLevel = ', naturalMaxLevel > 0 and naturalMaxLevel or 1, ',\n')
			out:write('\t},\n')
		end
	end
end
out:write('}')
out:close()

print("Skill data exported.")
