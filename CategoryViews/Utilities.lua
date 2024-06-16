Baganator.CategoryViews.Utilities = {}

-- Gets a table describing an item to be used in custom category's list of added
-- items
function Baganator.CategoryViews.Utilities.GetAddedItemData(itemID, itemLink)
  local petID = tonumber((itemLink:match("battlepet:(%d+)")))

  if petID then
    return { petID = petID }
  else
    return { itemID = itemID }
  end
end

function Baganator.CategoryViews.Utilities.GetBagTypes(characterData, section, indexes)
  local result = {}
  local containerInfo = characterData.containerInfo[section] or {}

  for index, bagID in ipairs(indexes) do
    local details = containerInfo[index - 1]
    local itemID = details and details.itemID

    table.insert(result, Baganator.Utilities.GetBagType(bagID, itemID))
  end
  return result
end
