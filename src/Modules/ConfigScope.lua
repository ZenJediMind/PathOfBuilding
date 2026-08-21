-- Path of Building
--
-- Module: Config Scope
-- Classifies Configuration options as shared (encounter), actor, or player-only.
--
local ConfigScope = { }

local PLAYER_VARS = {
	resistancePenalty = true,
	bandit = true,
	pantheonMajorGod = true,
	pantheonMinorGod = true,
	ignoreItemDisablers = true,
	ignoreJewelLimits = true,
}

local PLAYER_SECTIONS = {
	["Skill Options"] = true,
}

local SHARED_SECTIONS = {
	["Enemy Stats"] = true,
	["Map Modifiers and Player Debuffs"] = true,
}

local scopeByVar = { }
local indexed = false

local function inferScope(varData, sectionScope)
	if varData.scope then
		return varData.scope
	end
	local var = varData.var or ""
	if var:match("^playerCursed") then
		return "actor"
	end
	if PLAYER_VARS[var] or var:match("^minions") or var:match("^overrideEmpty") then
		return "player"
	end
	if varData.ifMinionCond then
		return "player"
	end
	if varData.ifEnemyCond or varData.ifEnemyMult or varData.ifEnemyStat
		or var:match("^enemy") or var:match("^conditionEnemy")
		or var:match("^MapPrefix") or var:match("^MapSuffix")
		or var:match("^multiplierMap") or var == "multiplierSextant" or var == "PvpScaling"
		or var:match("OnEnemy") or var == "ShockStacks" or var == "ScorchStacks"
	then
		return "shared"
	end
	return sectionScope or "actor"
end

function ConfigScope.index(varList)
	scopeByVar = { }
	local sectionScope = "actor"
	for _, varData in ipairs(varList or { }) do
		if varData.section then
			if PLAYER_SECTIONS[varData.section] then
				sectionScope = "player"
			elseif SHARED_SECTIONS[varData.section] then
				sectionScope = "shared"
			else
				sectionScope = varData.scope or "actor"
			end
		end
		if varData.var then
			local scope = inferScope(varData, sectionScope)
			scopeByVar[varData.var] = scope
			varData.resolvedScope = scope
		end
	end
	indexed = true
end

function ConfigScope.forVar(var)
	if not var then
		return "actor"
	end
	return scopeByVar[var] or "actor"
end

function ConfigScope.forVarData(varData)
	if varData and varData.resolvedScope then
		return varData.resolvedScope
	end
	if varData and varData.var then
		return ConfigScope.forVar(varData.var)
	end
	return "actor"
end

function ConfigScope.isIndexed()
	return indexed
end

return ConfigScope
