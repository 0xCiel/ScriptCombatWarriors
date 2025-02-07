local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

local Window = Library:CreateWindow({
    Title = 'Combat Warriors | Ciel | @0xciel',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Main = Window:AddTab('Main'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

Library:Notify("Loaded", 5) 

local char = game.Players.LocalPlayer.Character
local humanoid = char:WaitForChild("Humanoid")
local Camera = game:GetService("Workspace").CurrentCamera
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local isSpaceHeld = false
local isControlHeld = false
local isWHeld = false
local isSHeld = false
local isAHeld = false
local isDHeld = false
local FlyToggle = false
local speedHackEnabled = false
local bodyVelocity = nil
local SpeedC = 50
local FlySpeed = 50

local AutoParry = Tabs.Main:AddLeftGroupbox('Auto Parry')
local Misc = Tabs.Main:AddLeftGroupbox('Misc')
local Misc2 = Tabs.Main:AddRightGroupbox('Misc 2')

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local Camera = game:GetService("Workspace").CurrentCamera
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local LocalPlayer = Players.LocalPlayer

local SelfActor = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
local isAimbotEnabled = false
local fovAngle = 45
local smoothness = 0.3
local onlyVisible = true
local aimPoint = "head"
local performTeamCheck = false
local predictionMultiplier = 1
local AimbotToggle = false
local headSize = 15
local HitboxTransparency = 1
local HitboxResizer = false
local AirDropNotifier = false
local AirDropHighlight = false

local CONFIG = {
    ATTACK_RANGE = 25, 
    PREDICTION_THRESHOLD = 0.65, 
    BASE_REACTION_TIME = 0.08, 
    SHIELD_COOLDOWN = 0.3, 
    VELOCITY_THRESHOLD = 8, 
    ANIMATION_TRACK_NAMES = {
        "slash", "swing", "attack", "punch", "kick"
    },
    DEBUG_MODE = false
}

local State = {
    autoParryEnabled = false,
    lastShieldTime = 0,
    knownAnimations = {},
    threatLevels = {},
    recentAttackers = {}
}

local PredictionSystem = {
    velocityHistory = {}, 
    maxHistoryLength = 10,

    updateVelocityHistory = function(self, player, velocity)
        if not self.velocityHistory[player] then
            self.velocityHistory[player] = {}
        end

        table.insert(self.velocityHistory[player], velocity)
        if #self.velocityHistory[player] > self.maxHistoryLength then
            table.remove(self.velocityHistory[player], 1)
        end
    end,

    predictNextPosition = function(self, player)
        local history = self.velocityHistory[player]
        if not history or #history < 2 then return nil end

        local averageVelocity = Vector3.new(0, 0, 0)
        local weightSum = 0

        for i, velocity in ipairs(history) do
            local weight = i / #history 
            averageVelocity = averageVelocity + (velocity * weight)
            weightSum = weightSum + weight
        end

        averageVelocity = averageVelocity / weightSum
        return player.Character.HumanoidRootPart.Position + (averageVelocity * 0.1)
    end
}

local function createBodyVelocity()
    if not bodyVelocity then
        bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.MaxForce = Vector3.new(0, 0, 0)
        bodyVelocity.Parent = char.HumanoidRootPart
    end
end

function GetAllActors()
    local characters = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if not performTeamCheck or player.Team ~= Players.LocalPlayer.Team then
            local character = player.Character
            if character and character ~= SelfActor then
                table.insert(characters, character)
            end
        end
    end
    return characters
end

function IsVisible(target)
    local screenPoint, onScreen = Camera:WorldToViewportPoint(target.Position)
    if onScreen then
        local ray = Ray.new(Camera.CFrame.Position, (target.Position - Camera.CFrame.Position).unit * 500)
        local part = workspace:FindPartOnRayWithIgnoreList(ray, {SelfActor, Camera})
        if part and part:IsDescendantOf(target.Parent) then
            return true
        end
    end
    return false
end

function IsWithinFOV(target, fov)
    local directionToTarget = (target.Position - Camera.CFrame.Position).unit
    local cameraLookVector = Camera.CFrame.LookVector
    local angle = math.deg(math.acos(cameraLookVector:Dot(directionToTarget)))

    return angle <= fov / 2
end

function GetAimPosition(character)
    if aimPoint == "head" then
        return character:WaitForChild("Head").Position
    elseif aimPoint == "torso" then
        return character:WaitForChild("HumanoidRootPart").Position
    elseif aimPoint == "legs" then
        return (character:WaitForChild("LeftLeg").Position + character:WaitForChild("RightLeg").Position) / 2
    elseif aimPoint == "random" then
        local parts = {"Head", "HumanoidRootPart", "LeftLeg", "RightLeg"}
        local selectedPart = parts[math.random(1, #parts)]
        return character:WaitForChild(selectedPart).Position
    end
end

function GetNearestActorWithinFOV(fov)
    local nearestActor = nil
    local shortestDistance = math.huge

    for _, character in ipairs(GetAllActors()) do
        local targetPosition = character:WaitForChild("HumanoidRootPart").Position
        if IsWithinFOV(character:WaitForChild("HumanoidRootPart"), fov) then
            if not onlyVisible or IsVisible(character:WaitForChild("HumanoidRootPart")) then
                local screenPoint = Camera:WorldToViewportPoint(targetPosition)
                local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                local distanceFromCenter = (Vector2.new(screenPoint.X, screenPoint.Y) - screenCenter).Magnitude

                if distanceFromCenter < shortestDistance then
                    nearestActor = character
                    shortestDistance = distanceFromCenter
                end
            end
        end
    end

    return nearestActor
end

function LockCameraOnActor(actor)
    if actor then
        local targetPosition = GetAimPosition(actor)
        local currentCFrame = Camera.CFrame
        local targetCFrame = CFrame.new(Camera.CFrame.Position, targetPosition)
        Camera.CFrame = currentCFrame:Lerp(targetCFrame, smoothness)
    end
end


local function activateShield(threatLevel)
    local currentTime = os.clock()
    if currentTime - State.lastShieldTime < CONFIG.SHIELD_COOLDOWN then return end

    local adjustedReactionTime = CONFIG.BASE_REACTION_TIME * (1 - threatLevel * 0.3)
    task.wait(adjustedReactionTime)

    State.lastShieldTime = currentTime
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.wait() 
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)

    if CONFIG.DEBUG_MODE then
        print(string.format("Shield activated (Threat Level: %.2f)", threatLevel))
    end
end

local function setupAnimationTracking(character)
    local humanoid = character:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    local function onAnimationPlayed(animTrack)
        local animName = animTrack.Animation.Name:lower()

        for _, attackName in ipairs(CONFIG.ANIMATION_TRACK_NAMES) do
            if animName:find(attackName) then
                State.knownAnimations[animTrack] = {
                    name = animName,
                    timeStarted = os.clock()
                }
                break
            end
        end
    end

    animator.AnimationPlayed:Connect(onAnimationPlayed)
end

local function calculateThreatLevel(player)
    local character = player.Character
    if not character or not LocalPlayer.Character then return 0 end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot or not localRoot then return 0 end

    local distance = (localRoot.Position - targetRoot.Position).Magnitude
    if distance > CONFIG.ATTACK_RANGE then return 0 end

    local threatLevel = 0

    threatLevel = threatLevel + (1 - (distance / CONFIG.ATTACK_RANGE)) * 0.4

    local velocity = targetRoot.Velocity
    local speedThreat = math.clamp(velocity.Magnitude / 20, 0, 1) * 0.3
    threatLevel = threatLevel + speedThreat

    local directionToLocal = (localRoot.Position - targetRoot.Position).Unit
    local movementAlignment = directionToLocal:Dot(velocity.Unit)
    if movementAlignment > CONFIG.PREDICTION_THRESHOLD then
        threatLevel = threatLevel + 0.3
    end

    local animator = character:FindFirstChild("Humanoid"):FindFirstChild("Animator")
    if animator then
        for _, track in pairs(animator:GetPlayingAnimationTracks()) do
            if State.knownAnimations[track] then
                threatLevel = threatLevel + 0.4
                break
            end
        end
    end

    return math.clamp(threatLevel, 0, 1)
end

RunService.RenderStepped:Connect(function()
if AimbotToggle then
	 if isAimbotEnabled then
        local nearestActor = GetNearestActorWithinFOV(fovAngle)
        if nearestActor then
            LockCameraOnActor(nearestActor)
        end
    end
end
end)
RunService.RenderStepped:connect(function()
    if HitboxResizer then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Name ~= LocalPlayer.Name then
                pcall(function()
                    local head = player.Character.Head
                    head.Size = Vector3.new(headSize, headSize, headSize)
                    head.Transparency = HitboxTransparency
                    head.BrickColor = BrickColor.new("Red")
                    head.Material = "Neon"
                    head.CanCollide = false
                    head.Massless = true
                end)
            end
        end
    end
end)

game.workspace.Map.DescendantAdded:Connect(function(obj)
    if AirDropNotifier and (obj.Name == "Airdrop" or obj.Name == "SpecAirdrop" or obj.Name == "MythicalAirdrop") then
        Library:Notify(obj.Name .. ' has been dropped', 10)
    end

    if AirDropHighlight and (obj.Name == "Airdrop" or obj.Name == "SpecAirdrop" or obj.Name == "MythicalAirdrop") then
        local highlight = Instance.new("Highlight")
        highlight.Parent = obj:FindFirstChild("Crate")
    end
end)

RunService.Heartbeat:Connect(function()
    if not State.autoParryEnabled then return end

    local highestThreat = 0
    local mostDangerousPlayer = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local threatLevel = calculateThreatLevel(player)

            if threatLevel > highestThreat then
                highestThreat = threatLevel
                mostDangerousPlayer = player
            end

            if player.Character:FindFirstChild("HumanoidRootPart") then
                PredictionSystem:updateVelocityHistory(player, player.Character.HumanoidRootPart.Velocity)
            end
        end
    end

    if highestThreat > 0.6 then
        activateShield(highestThreat)
    end
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        setupAnimationTracking(character)
    end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        setupAnimationTracking(player.Character)
    end
    player.CharacterAdded:Connect(function(character)
        setupAnimationTracking(character)
    end)
end

AutoParry:AddToggle('Auto Parry', {
    Text = 'Auto Parry',
    Default = false,
    Tooltip = 'Auto Parry',
    Callback = function(Value)
        State.autoParryEnabled = Value
    end
})

AutoParry:AddSlider('Attack Range', {
    Text = 'Attack Range',
    Default = 25,
    Min = 1,
    Max = 50,
    Rounding = 1,
    Callback = function(Value)
        CONFIG.ATTACK_RANGE = Value
    end
})

AutoParry:AddSlider('Prediction Threshold', {
    Text = 'Prediction Threshold',
    Default = 0.65,
    Min = 0,
    Max = 25,
    Rounding = 1,
    Callback = function(Value)
        CONFIG.PREDICTION_THRESHOLD = Value
    end
})

AutoParry:AddSlider('Reaction Time', {
    Text = 'Reaction Time',
    Default = 0.08,
    Min = 0,
    Max = 10,
    Rounding = 1,
    Callback = function(Value)
        CONFIG.BASE_REACTION_TIME = Value
    end
})

Misc:AddToggle('Hitbox Resizer', {
    Text = 'Hitbox Resizer',
    Default = false,
    Tooltip = 'Hitbox Resizer',
    Callback = function(Value)
        HitboxResizer = Value
    end
})

Misc:AddSlider('Hitbox Size', {
    Text = 'Hitbox Size',
    Default = 15,
    Min = 1,
    Max = 50,
    Rounding = 1,
    Callback = function(Value)
        headSize = Value
    end
})

Misc:AddToggle('Airdrop Notifier', {
    Text = 'AirDrop Notifier',
    Default = false,
    Tooltip = 'AirDrop Notifier',
    Callback = function(Value)
        AirDropNotifier = Value
    end
})

Misc:AddToggle('Highlight Airdrop', {
    Text = 'Highlight Airdrop',
    Default = false,
    Tooltip = 'Highlight Airdrop',
    Callback = function(Value)
        AirDropHighlight = Value
    end
})
Misc2:AddToggle('Aimbot', {
    Text = 'Aimbot',
    Default = false,
    Tooltip = 'Aimbot',
    Callback = function(Value)
AimbotToggle = Value
	end
}):AddKeyPicker('AimbotKeybind', {
    Default = 'R', 
    SyncToggleState = true,
    Mode = 'Toggle',
    Text = 'Aimbot Keybind',
    NoUI = false,
   Callback = function(Value)
        isAimbotEnabled = Value
    end,
})

Misc2:AddSlider('Aimbot Prediction Offset', {
    Text = 'Aimbot Prediction Offset',
    Default = 1,
    Min = 0,
    Max = 20,
    Rounding = 1,
    Callback = function(Value)
        predictionMultiplier = Value
    end
})

Misc:AddToggle('Fly', {
    Text = 'Fly',
    Default = false,
    Tooltip = 'Fly',
    Callback = function(Value)
        FlyToggle = Value
        createBodyVelocity()
    end
}):AddKeyPicker('FlyKeybind', {
    Default = 'J',
    SyncToggleState = true,
    Mode = 'Toggle',
    Text = 'Fly Keybind',
    NoUI = false,
    Callback = function(Value)
        Toggles.Fly:SetValue(Value)
    end,
})

Misc:AddSlider('FlySpeed', {
    Text = 'Fly Speed',
    Default = 50,
    Min = 0,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        FlySpeed = Value
    end
})

Misc:AddToggle('WalkSpeed', {
    Text = 'Walk Speed',
    Default = false,
    Tooltip = 'Walk Speed',
    Callback = function(Value)
        speedHackEnabled = Value
        createBodyVelocity()
    end
}):AddKeyPicker('WalkSpeedKeyBind', {
    Default = 'N',
    SyncToggleState = true,
    Mode = 'Toggle',
    Text = 'WalkSpeed Keybind',
    NoUI = false,
    Callback = function(Value)
        Toggles.WalkSpeed:SetValue(Value)
    end,
})

Misc:AddSlider('SpeedMultiplier', {
    Text = 'Speed Multiplier',
    Default = 50,
    Min = 0,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        SpeedC = Value
    end
})

local function updateVelocity()
    if not bodyVelocity then return end

    local forwardVelocity = Vector3.new(0, 0, 0)
    local upwardVelocity = Vector3.new(0, 0, 0)
    local sidewaysVelocity = Vector3.new(0, 0, 0)

    if FlyToggle then
        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        if isSpaceHeld then
            upwardVelocity = Vector3.new(0, FlySpeed, 0)
        elseif isControlHeld then
            upwardVelocity = Vector3.new(0, -FlySpeed, 0)
        end

        if isWHeld then
            forwardVelocity = Camera.CFrame.LookVector * FlySpeed
        elseif isSHeld then
            forwardVelocity = -Camera.CFrame.LookVector * FlySpeed
        end

        if isAHeld then
            sidewaysVelocity = -Camera.CFrame.RightVector * FlySpeed
        elseif isDHeld then
            sidewaysVelocity = Camera.CFrame.RightVector * FlySpeed
        end
    elseif speedHackEnabled then
        bodyVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
        if humanoid.MoveDirection.Magnitude > 0 then
            forwardVelocity = humanoid.MoveDirection * SpeedC
        end
    else
        bodyVelocity.MaxForce = Vector3.new(0, 0, 0)
    end

    bodyVelocity.Velocity = forwardVelocity + upwardVelocity + sidewaysVelocity
end

UIS.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Space then
        isSpaceHeld = true
    elseif input.KeyCode == Enum.KeyCode.LeftControl then
        isControlHeld = true
    elseif input.KeyCode == Enum.KeyCode.W then
        isWHeld = true
    elseif input.KeyCode == Enum.KeyCode.S then
        isSHeld = true
    elseif input.KeyCode == Enum.KeyCode.A then
        isAHeld = true
    elseif input.KeyCode == Enum.KeyCode.D then
        isDHeld = true
    end
    updateVelocity()
end)

UIS.InputEnded:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Space then
        isSpaceHeld = false
    elseif input.KeyCode == Enum.KeyCode.LeftControl then
        isControlHeld = false
    elseif input.KeyCode == Enum.KeyCode.W then
        isWHeld = false
    elseif input.KeyCode == Enum.KeyCode.S then
        isSHeld = false
    elseif input.KeyCode == Enum.KeyCode.A then
        isAHeld = false
    elseif input.KeyCode == Enum.KeyCode.D then
        isDHeld = false
    end
    updateVelocity()
end)

RunService.RenderStepped:Connect(function()
    updateVelocity()
end)


Library:SetWatermarkVisibility(true)

local FrameTimer, FrameCounter, FPS = tick(), 0, 60
local WatermarkConnection = RunService.RenderStepped:Connect(function()
    FrameCounter += 1
    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter
        FrameTimer, FrameCounter = tick(), 0
    end
    Library:SetWatermark(('Test | %s fps | %s ms'):format(
        math.floor(FPS),
        math.floor(game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue())
    ))
end)

Library:OnUnload(function()
    WatermarkConnection:Disconnect()
    print('Unloaded!')
    Library.Unloaded = true
end)

local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder('MyScriptHub')
SaveManager:SetFolder('MyScriptHub/CombatWarriors')
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])
SaveManager:LoadAutoloadConfig()
