component = require("component")
sides = require("sides")
robot = require("robot")
inv = component.inventory_controller
geo = component.geolyzer
db = component.database
local me = component.upgrade_me
local itemStack2 = component.upgrade_me.getItemsInNetwork()
sleepAmount = 5

x = 0
y = 0
z = 0
direction = "NORTH"


-- config object class
config = {}
config.__index = config

-- Constructor for config
function config.new(entries)
    local self = setmetatable({}, config)
    self.entries = entries or {} -- Default to an empty table if no entries are provided
    return self
end

-- Method to add an entry to the config
function config:addEntry(useItem, action)
    table.insert(self.entries, { useItem = useItem, action = action })
end

-- Method to get all entries in the config
function config:getEntries()
    return self.entries
end

-- block object class
block = {}
block.__index = block

-- Constructor for block
function block.new(name, direction, config)
    local self = setmetatable({}, block)
    self.name = name or "air"               -- Default to "Unnamed block"
    self.direction = direction or "UNKNOWN" -- Default to "none"
    self.config = config or config.new()    -- Default to a new config object
    return self
end

-- Method to set the block's direction
function block:setDirection(direction)
    self.direction = direction
end

-- Method to add an entry to the block's config
function block:addConfigEntry(useItem, action)
    self.config:addEntry(useItem, action)
end

-- Method to display block details
function block:display()
    print("block Name: " .. self.name)
    print("Direction: " .. self.direction)
    print("config Entries:")
    for i, entry in ipairs(self.config:getEntries()) do
        print(string.format("  Entry %d - Use Item: %s, Action: %s", i, entry.useItem, entry.action))
    end
end

function moveTo(destX, destY, destZ)
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function newAutotable(dim)
    local MT = {};
    for i = 1, dim do
        MT[i] = {
            __index = function(t, k)
                if i < dim then
                    t[k] = setmetatable({}, MT[i + 1])
                    return t[k];
                end
            end
        }
    end

    return setmetatable({}, MT[1]);
end

function getBlockInfo()
    local scan = geo.analyze(sides.front)
    local direction = "NORTH"
    local name = "air"

    if scan["name"] then
        if scan["name"] == "minecraft:air" then
            return direction, name
        end
    end

    if scan["facing"] then
        if not scan["facing"] == "UNKNOWN" then
            direction = scan["facing"]
        end
    end

    if robot.swing(sides.front) then
        os.sleep(0.6)
        local item = inv.getStackInInternalSlot(1)
        if item["label"] then
            name = item["label"]
        end
        storeEnderChest()
    end
    return direction, name
end

--store slot 1 item inside the ender chest at given slot of robot
function storeEnderChest(slot)
    robot.select(slot)
    robot.place(sides.front, true)
    robot.select(1)
    os.sleep(0.6)
    if not robot.drop(sides.front, 1) then
        print("ERROR: ENDER CHEST FULL")
        return false
    end
    if not robot.swing(sides.front) then
        return false
    end
    robot.transferTo(slot, 1)
    return true
end

function parseMultiblock(width, height, length)
    local x = 0
    local y = 0
    local z = 0
end

function checkCPUs(cpusNeeded)
    while true do
        local cpus = me.getCpus()
        local occupiedCpus = 0
        for i = 1, #cpus do
            if cpus[i].busy then occupiedCpus = occupiedCpus + 1 end
        end
        if occupiedCpus + cpusNeeded < #cpus then return true end
        print("ERROR no CPUs, waiting 60s")
        os.sleep(sleepAmount)
    end
end

function craftItems(items)
    local order = {}
    local beforeCounts = {}
    for i, item in pairs(items) do
        local itemLabel = item.itemLabel
        local currItem = me.getItemsInNetwork({ label = itemLabel })
        beforeCounts[i] = currItem[1].size
    end

    checkCPUs(#items)

    --Order items
    local tracker = 1;
    for _, item in pairs(items) do
        local itemLabel = item.itemLabel
        local quantity = item.quantity
        local attempts = 0
        while true do
            --if attempts > 3 then return false end

            local recipes = me.getCraftables({ label = itemLabel })

            --check if can order
            while #recipes ~= 1 do
                print("ERROR no valid recipe found for " .. itemLabel)
                os.sleep(sleepAmount)
            end
            checkCPUs(1)

            --order item, cpu found
            print("CPU found, attempting order " .. itemLabel)
            order[tracker] = recipes[1].request(quantity)
            if order[tracker].hasFailed() then
                print("Error: Failed to order " .. itemLabel)
                attempts = attempts + 1
                os.sleep(1)
            else
                break
            end
        end
        tracker = tracker + 1
    end

    --Check if orders were successful
    local doneCount = 0
    while doneCount < #items do
        doneCount = 0
        local tracker2 = 1
        for _, item in pairs(items) do
            local itemLabel = item.itemLabel
            local quantity = item.quantity
            local currNumItems = me.getItemsInNetwork({ label = itemLabel })
            local obtained = currNumItems[1].size - beforeCounts[tracker2]
            if order[tracker2].isDone() or obtained >= quantity then
                print("1 item of " .. itemLabel .. " crafted")
                doneCount = doneCount + 1
            end
            tracker2 = tracker2 + 1
        end
        os.sleep(sleepAmount)
    end
end

-- Function to retrieve items from the ME system and craft missing ones
function getItems(items)
    local itemCounts = {} 
    local itemsToOrder = {}

    for _, item in pairs(items) do
        local itemLabel = item.itemLabel
        local quantity = item.quantity
        local currNumItems = me.getItemsInNetwork({ label = itemLabel })
        --if there is an item that is less than requested, add to shopping cart
        if currNumItems < item.quantity then
            itemsToOrder[itemLabel] = item.quantity - currNumItems
        else
            me.store({label=itemLabel}, db.address, 1)
            me.requestItems(db.address, 1, quantity)
        end
    end

    if itemsToOrder ~= nil then
        craftItems(itemsToOrder)
        for _, item in pairs(items) do
            local itemLabel = item.itemLabel
            local quantity = item.quantity
            me.store({label=itemLabel}, db.address, 1)
            me.requestItems(db.address, 1, quantity)
        end
    end
end

--me.store({label=itemLabel}, db.address, 1)
--me.requestItems(db.address, 1, quantity)
blockMap = newAutotable(3)
--local dir, name = getBlockInfo()
local myConfig = config.new()
myConfig:addEntry("Hammer", "Build")
myConfig:addEntry("Wrench", "Tighten")
local myBlock = block.new(name, dir, myConfig)
myBlock:display()

if component.upgrade_me.isLinked() then
    print("hello")
    getItems({ { itemLabel = "Oak Wood Planks", quantity = 3 }, { itemLabel = "Stone", quantity = 5 }, { itemLabel = "End Stone", quantity = 7 } })
    --craftItems({ { itemLabel = "Large Processing Factory", quantity = 1 } })
end
