local BadgeService = game:GetService("BadgeService")
local BadgeHelper = {}

function BadgeHelper:AwardBadge(player : Instance, badgeId)
    local success, hasBadge = pcall(function()
        return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
    end)
    if success then
        if not hasBadge then
            local success, result = pcall(function()
                return BadgeService:AwardBadge(player.UserId, badgeId)
            end)
            if not success then
                warn("Failed to award badge " .. badgeId .. " to " .. player.Name .. ": " .. result)
            end
        end
    else
        warn("Failed to check badge ownership", badgeId, hasBadge)
    end
end

return BadgeHelper