-- Mercenary extraction helpers. This module is only loaded by the exporter.
local MercenaryExport = { }

function MercenaryExport.rowId(row)
	if row then
		return type(row.Id) == "table" and row.Id.Id or row.Id
	end
end

function MercenaryExport.sortedRows(name)
	local rows = { }
	for row in dat(name):Rows() do
		table.insert(rows, row)
	end
	table.sort(rows, function(a, b) return MercenaryExport.rowId(a) < MercenaryExport.rowId(b) end)
	return rows
end

function MercenaryExport.rowIds(rows)
	local ids = { }
	for _, row in ipairs(rows) do
		table.insert(ids, MercenaryExport.rowId(row))
	end
	table.sort(ids)
	return ids
end

function MercenaryExport.uniqueSorted(values)
	local seen, result = { }, { }
	for _, value in ipairs(values) do
		if not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end
	table.sort(result)
	return result
end

local function templateProperties(text, blockName)
	local properties = { }
	local block = text:match("%f[%w]"..blockName.."%s*{(.-)}") or ""
	for line in block:gmatch("[^\r\n]+") do
		local key, value = line:gsub("//.*", ""):match("^%s*([^%s=]+)%s*=%s*(.-)%s*$")
		if key then
			if value == "true" then
				properties[key] = true
			elseif value == "false" then
				properties[key] = false
			else
				properties[key] = tonumber(value) or value
			end
		end
	end
	return properties
end

local objectTemplates = { }
function MercenaryExport.objectTemplate(objectType)
	if not objectType or objectType == "nothing" or objectType == "Metadata/Monsters/Monster" then
		return { stats = { }, monsterProperties = { } }
	end
	if objectTemplates[objectType] then
		return objectTemplates[objectType]
	end
	local rawText = assert(getFile(objectType..".ot"), "Missing Mercenary object template: "..objectType)
	local text = convertUTF16to8(rawText)
	local parent = MercenaryExport.objectTemplate(text:match('extends "([^"]+)"'))
	local template = { stats = copyTable(parent.stats, true), monsterProperties = copyTable(parent.monsterProperties) }
	for id, value in pairsSortByKey(templateProperties(text, "Stats")) do
		table.insert(template.stats, { id = id, value = value, source = objectType })
	end
	for key, value in pairs(templateProperties(text, "Monster")) do
		template.monsterProperties[key] = value
	end
	objectTemplates[objectType] = template
	return template
end

function MercenaryExport.appendModStats(mods, stats)
	for _, modRow in ipairs(mods) do
		for index = 1, 8 do
			local stat = modRow["Stat"..index]
			if stat then
				local value = index <= 6 and modRow["Stat"..index.."Value"][1] or modRow["Stat"..index.."Min"]
				table.insert(stats, { id = stat.Id, value = value, source = modRow.Id })
			end
		end
	end
end

local function constantStatValue(effect, wantedId)
	for index, stat in ipairs(effect.GrantedEffectStatSets.ConstantStats) do
		if stat.Id == wantedId then
			return effect.GrantedEffectStatSets.ConstantStatsValues[index]
		end
	end
end

function MercenaryExport.summonedMonster(effect)
	local summonedId = constantStatValue(effect, "alternate_minion")
	if summonedId then
		local summoned = dat("SummonedSpecificMonsters"):GetRow("Id", summonedId)
		assert(summoned and summoned.MonsterVarietiesKey, "Missing Mercenary summoned monster: "..effect.Id.." -> "..summonedId)
		return summoned.MonsterVarietiesKey, summoned
	end
end

function MercenaryExport.displayMinion(effect)
	local id = constantStatValue(effect, "display_minion_monster_type")
	if id then
		return assert(dat("DisplayMinionMonsterType"):GetRow("Id", id), "Missing Mercenary display minion: "..id)
	end
end

function MercenaryExport.buffPayload(effect)
	local source = dat("AddBuffToTargetVarieties")
	local row = assert(source:GetRowByIndex(effect.SkillID + 1), "Missing Mercenary buff payload: "..effect.Id)
	return {
		buffId = row.BuffDefinitions.Id,
		values = source:ReadCell(row._rowIndex, 2),
		statIds = MercenaryExport.orderedRowIds(row.StatsKeys),
	}, row.BuffDefinitions
end

function MercenaryExport.applySkillMetadata(skill, effect, mercenaries, out)
	if effect.CooldownNotRecoverDuringActive then
		table.insert(skill.constantStats, { "display_this_skill_cooldown_does_not_recover_during_buff", 1 })
	end
	local minion = mercenaries.defaultMinions[effect.displayMinionId]
	if minion then out:write('\tminionList = { "', minion.minionId, '" },\n') end
	if effect.activeSkill.ActionType ~= "AddBuffToTarget" then return end
	local payload = mercenaries.actionBuffs[effect.SkillID]
	local buff = mercenaries.buffs[payload.buffId]
	assert(#payload.values + #payload.statIds == #buff.Stats, "Mercenary buff stat/value mismatch: "..effect.Id)
	for index, value in ipairs(payload.values) do
		table.insert(skill.constantStats, { buff.Stats[index], value })
	end
	for index, id in ipairs(payload.statIds) do
		assert(buff.Stats[#payload.values + index] == id, "Mercenary dynamic buff stat mismatch: "..effect.Id)
	end
end

function MercenaryExport.monsterEffects(monster)
	local effects = { }
	for _, effect in ipairs(monster.GrantedEffects) do table.insert(effects, effect) end
	for _, mods in ipairs({ monster.Mods, monster.SpecialMods }) do
		for _, mod in ipairs(mods) do
			if mod.Daemon ~= "" then
				local daemon = assert(dat("MonsterVarieties"):GetRow("Id", mod.Daemon), "Missing Mercenary daemon: "..mod.Daemon)
				for _, effect in ipairs(daemon.GrantedEffects) do table.insert(effects, effect) end
			end
		end
	end
	return effects
end

local function collectEffect(effects, effect)
	if not effect or effects[effect.Id] then return end
	effects[effect.Id] = effect
	local monster = MercenaryExport.summonedMonster(effect)
	if monster then
		for _, minionEffect in ipairs(MercenaryExport.monsterEffects(monster)) do collectEffect(effects, minionEffect) end
	end
end

function MercenaryExport.skillEffects()
	local effects = { }
	for row in dat("MercenarySkills"):Rows() do
		collectEffect(effects, row.Id)
		collectEffect(effects, row.EncounterGrantedEffect)
	end
	for row in dat("MercenaryClasses"):Rows() do
		for _, effect in ipairs(MercenaryExport.monsterEffects(row.MonsterVarietyAllied)) do collectEffect(effects, effect) end
	end
	return effects
end

function MercenaryExport.fields(row, names)
	local result = { }
	for name in names:gmatch("%S+") do result[name] = row[name] end
	return result
end

local function addSkillCandidate(index, key, id, category)
	index[key] = index[key] or { gems = { }, skills = { }, supports = { } }
	table.insert(index[key][category], id)
end

local function skillCategory(effect)
	if effect.IsSupport then return "supports" end
	local gems = dat("GemEffects")
	if gems:GetRow("GrantedEffect", effect) or gems:GetRow("GrantedEffect2", effect) then return "gems" end
	return "skills"
end

function MercenaryExport.skillBaseIndexes()
	local ids, activeSkills, names = { }, { }, { }
	for _, name in ipairs({ "act_str", "act_dex", "act_int", "other", "glove", "minion", "spectre", "sup_str", "sup_dex", "sup_int" }) do
		for line in io.lines("Skills/"..name..".txt") do
			local id = line:match("^#skill%s+(%S+)")
			if id then ids[id] = true end
		end
	end
	for id in pairsSortByKey(ids) do
		local effect = dat("GrantedEffects"):GetRow("Id", id)
		if effect and effect.ActiveSkill then
			local category = skillCategory(effect)
			addSkillCandidate(activeSkills, effect.ActiveSkill.Id, id, category)
			if effect.ActiveSkill.DisplayName ~= "" then
				addSkillCandidate(names, effect.ActiveSkill.DisplayName, id, category)
			end
		end
	end
	return activeSkills, names
end

function MercenaryExport.supportColors()
	-- Mercenary-only icons use PoB's gold and combined-attribute palette.
	local colors = {
		["Art/2DItems/Gems/Support/MercGoldSupportGem.dds"] = "RARE",
		["Art/2DItems/Gems/Support/MercSilverStrSupportGem.dds"] = "STRENGTH",
		["Art/2DItems/Gems/Support/MercSilverIntSupportGem.dds"] = "INTELLIGENCE",
		["Art/2DItems/Gems/Support/MercSilverStrDexSupportGem.dds"] = "DUELIST",
		["Art/2DItems/Gems/Support/MercSilverStrIntSupportGem.dds"] = "TEMPLAR",
		["Art/2DItems/Gems/Support/MercSilverDexIntSupportGem.dds"] = "SHADOW",
	}
	local attributes = { "STRENGTH", "DEXTERITY", "INTELLIGENCE", "NORMAL" }
	local supportIcons = { }
	for support in dat("MercenarySupports"):Rows() do supportIcons[support.GemIcon] = true end
	for gem in dat("SkillGems"):Rows() do
		local icon = gem.BaseItemType.ItemVisualIdentityKey.DDSFile
		for _, variant in ipairs(gem.GemVariants) do
			local effect = variant.GrantedEffect
			if supportIcons[icon] and effect and effect.IsSupport then
				local color = assert(attributes[effect.Attribute], "Unknown support attribute: "..effect.Id)
				assert(not colors[icon] or colors[icon] == color, "Conflicting support colors: "..icon)
				colors[icon] = color
			end
		end
	end
	return colors
end

function MercenaryExport.writeData(name, data)
	local out = assert(io.open("../Data/"..name..".lua", "w"))
	out:write("-- This file is automatically generated, do not edit!\n-- Mercenary data (c) Grinding Gear Games\n\n")
	out:write("return ")
	writeLuaTable(out, data, 1)
	out:write("\n")
	out:close()
end

-- Unlike rowIds, these lists must retain their alignment with parallel values.
function MercenaryExport.orderedRowIds(rows)
	local ids = { }
	for _, row in ipairs(rows) do table.insert(ids, row.Id) end
	return ids
end

local function recordMinionFlags(rows, ids)
	for _, stat in ipairs(rows) do
		if stat.CannotGrantToMinion then table.insert(ids, stat.Id) end
	end
end

function MercenaryExport.minionStatFlags(statSet)
	local minionFlags = { }
	for _, rows in ipairs({ statSet.ConstantStats, statSet.ImplicitStats }) do recordMinionFlags(rows, minionFlags) end
	for _, row in ipairs(dat("GrantedEffectStatSetsPerLevel"):GetRowList("GrantedEffectStatSets", statSet)) do
		for _, key in ipairs({ "AdditionalBooleanStats", "FloatStats", "AdditionalStats" }) do recordMinionFlags(row[key], minionFlags) end
	end
	return MercenaryExport.uniqueSorted(minionFlags)
end

return MercenaryExport
