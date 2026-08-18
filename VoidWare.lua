local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==================== CLICK SOUND SYSTEM ====================
local function PlayClick(volume, pitch)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6895079853"
    sound.Volume = volume or 0.45
    sound.PlaybackSpeed = pitch or 1
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

local function PlayHover()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6895079853"
    sound.Volume = 0.18
    sound.PlaybackSpeed = 1.35
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

local function PlayToggleOn()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6895079853"
    sound.Volume = 0.4
    sound.PlaybackSpeed = 1.15
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

local function PlayToggleOff()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6895079853"
    sound.Volume = 0.35
    sound.PlaybackSpeed = 0.85
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

-- ==================== DISCORD WEBHOOK + CHAT SYSTEM ====================
local DiscordWebhookURL = ""
local DetectionSystemEnabled = false
local LastWebhookSend = 0
local WEBHOOK_COOLDOWN = 1.2

local DiscordBotToken = ""
local DiscordChannelId = ""
local LastMessages = {}
local ChatAutoRefresh = false
local ChatRefreshThread = nil

local function IsValidWebhook(url)
    if typeof(url) ~= "string" or #url < 20 then return false end
    return url:match("^https://discord%.com/api/webhooks/%d+/[%w%-_]+") 
        or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w%-_]+")
        or url:match("^https://canary%.discord%.com/api/webhooks/%d+/[%w%-_]+")
end

local function GetRequestFunc()
    return (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
end

local function SendDiscordWebhook(payload)
    if not IsValidWebhook(DiscordWebhookURL) then return false, "Invalid webhook URL" end
    if tick() - LastWebhookSend < WEBHOOK_COOLDOWN then return false, "Rate limited" end

    local requestFunc = GetRequestFunc()
    if not requestFunc then
        return false, "No HTTP request function available in this executor"
    end

    local success, response = pcall(function()
        return requestFunc({
            Url = DiscordWebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if success then
        LastWebhookSend = tick()
        return true
    end
    return false, tostring(response)
end

local function LogFeature(featureName, state, extra)
    if not DetectionSystemEnabled then return end
    if not IsValidWebhook(DiscordWebhookURL) then return end

    local statusText = state and "✅ ENABLED" or "❌ DISABLED"
    local color = state and 5763719 or 15548997

    local fields = {
        { name = "Player", value = player.Name .. " (`" .. tostring(player.UserId) .. "`)", inline = true },
        { name = "Feature", value = featureName, inline = true },
        { name = "Status", value = statusText, inline = true },
        { name = "Game", value = game.Name .. " | PlaceId: " .. tostring(game.PlaceId), inline = false },
        { name = "Time", value = "<t:" .. tostring(os.time()) .. ":F>", inline = true }
    }

    if extra and type(extra) == "table" then
        for _, f in ipairs(extra) do
            table.insert(fields, f)
        end
    end

    local embed = {
        title = "VoidWare Detection",
        description = "A feature was toggled inside VoidWare.",
        color = color,
        fields = fields,
        footer = { text = "VoidWare v2 • Detection System" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    task.spawn(function()
        SendDiscordWebhook({
            username = "VoidWare Logger",
            avatar_url = "https://cdn.discordapp.com/embed/avatars/0.png",
            embeds = { embed }
        })
    end)
end

local function LogCustom(title, description, color)
    if not IsValidWebhook(DiscordWebhookURL) then return end
    color = color or 5793266

    local embed = {
        title = title or "VoidWare",
        description = description or "",
        color = color,
        fields = {
            { name = "Player", value = player.Name .. " (`" .. tostring(player.UserId) .. "`)", inline = true },
            { name = "Game", value = game.Name, inline = true },
            { name = "Time", value = "<t:" .. tostring(os.time()) .. ":F>", inline = true }
        },
        footer = { text = "VoidWare v2" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    task.spawn(function()
        SendDiscordWebhook({
            username = "VoidWare Logger",
            avatar_url = "https://cdn.discordapp.com/embed/avatars/0.png",
            embeds = { embed }
        })
    end)
end

local function ResolveChannelFromWebhook()
    if not IsValidWebhook(DiscordWebhookURL) then return nil end
    local requestFunc = GetRequestFunc()
    if not requestFunc then return nil end

    local success, response = pcall(function()
        return requestFunc({
            Url = DiscordWebhookURL,
            Method = "GET",
            Headers = { ["Content-Type"] = "application/json" }
        })
    end)

    if success and response and response.Body then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)
        if ok and data and data.channel_id then
            return tostring(data.channel_id)
        end
    end
    return nil
end

local function FetchChannelMessages(limit)
    limit = limit or 15
    if DiscordBotToken == "" or DiscordBotToken == nil then
        return false, "No Bot Token set"
    end
    if DiscordChannelId == "" or DiscordChannelId == nil then
        local resolved = ResolveChannelFromWebhook()
        if resolved then
            DiscordChannelId = resolved
        else
            return false, "No Channel ID (apply webhook first or set Channel ID)"
        end
    end

    local requestFunc = GetRequestFunc()
    if not requestFunc then
        return false, "No HTTP request function available"
    end

    local url = "https://discord.com/api/v10/channels/" .. DiscordChannelId .. "/messages?limit=" .. tostring(limit)

    local success, response = pcall(function()
        return requestFunc({
            Url = url,
            Method = "GET",
            Headers = {
                ["Authorization"] = "Bot " .. DiscordBotToken,
                ["Content-Type"] = "application/json"
            }
        })
    end)

    if not success then
        return false, "Request failed: " .. tostring(response)
    end

    if not response or not response.Body then
        return false, "Empty response from Discord"
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not ok or type(data) ~= "table" then
        return false, "Failed to parse messages (check Bot Token + Message Content Intent + channel permissions)"
    end

    LastMessages = {}
    for i = #data, 1, -1 do
        local msg = data[i]
        if msg and msg.content and msg.content ~= "" then
            local author = "Unknown"
            if msg.author then
                author = msg.author.global_name or msg.author.username or "Unknown"
            end
            table.insert(LastMessages, {
                author = author,
                content = msg.content,
                timestamp = msg.timestamp or ""
            })
        end
    end

    return true, LastMessages
end

-- Neon floating button
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VoidWareNeonButton"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainButton = Instance.new("Frame")
mainButton.Name = "MainButton"
mainButton.Size = UDim2.new(0, 240, 0, 55)
mainButton.Position = UDim2.new(0, 15, 0, 15)
mainButton.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
mainButton.BorderSizePixel = 0
mainButton.Parent = screenGui

local innerFrame = Instance.new("Frame")
innerFrame.Name = "InnerGradient"
innerFrame.Size = UDim2.new(1, -2, 1, -2)
innerFrame.Position = UDim2.new(0, 1, 0, 1)
innerFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
innerFrame.BorderSizePixel = 0
innerFrame.Parent = mainButton

local c1 = Instance.new("UICorner")
c1.CornerRadius = UDim.new(0, 14)
c1.Parent = mainButton

local c2 = Instance.new("UICorner")
c2.CornerRadius = UDim.new(0, 12)
c2.Parent = innerFrame

local stroke1 = Instance.new("UIStroke")
stroke1.Color = Color3.fromRGB(255, 255, 255)
stroke1.Thickness = 1.8
stroke1.Transparency = 0.45
stroke1.Parent = mainButton

local stroke2 = Instance.new("UIStroke")
stroke2.Color = Color3.fromRGB(240, 240, 255)
stroke2.Thickness = 3.5
stroke2.Transparency = 0.65
stroke2.Parent = innerFrame

local iconContainer = Instance.new("Frame")
iconContainer.Size = UDim2.new(0, 45, 0, 45)
iconContainer.Position = UDim2.new(0, 8, 0, 5)
iconContainer.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
iconContainer.BorderSizePixel = 0
iconContainer.Parent = mainButton

local c3 = Instance.new("UICorner")
c3.CornerRadius = UDim.new(0, 10)
c3.Parent = iconContainer

local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(255, 255, 255)
iconStroke.Thickness = 1.2
iconStroke.Transparency = 0.4
iconStroke.Parent = iconContainer

local iconLabel = Instance.new("TextLabel")
iconLabel.Size = UDim2.new(1, 0, 1, 0)
iconLabel.BackgroundTransparency = 1
iconLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
iconLabel.TextSize = 24
iconLabel.Font = Enum.Font.GothamBold
iconLabel.Text = "✦"
iconLabel.Parent = iconContainer

local textContainer = Instance.new("Frame")
textContainer.Size = UDim2.new(1, -60, 1, 0)
textContainer.Position = UDim2.new(0, 60, 0, 0)
textContainer.BackgroundTransparency = 1
textContainer.Parent = mainButton

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 28)
titleLabel.Position = UDim2.new(0, 0, 0, 5)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(245, 245, 255)
titleLabel.TextSize = 15
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "VoidWare V2"
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = textContainer

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Size = UDim2.new(1, 0, 0, 17)
subtitleLabel.Position = UDim2.new(0, 0, 0, 30)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
subtitleLabel.TextSize = 10
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.Text = "Click to open UI • Press T"
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.Parent = textContainer

local clickButton = Instance.new("TextButton")
clickButton.Size = UDim2.new(1, 0, 1, 0)
clickButton.BackgroundTransparency = 1
clickButton.BorderSizePixel = 0
clickButton.Text = ""
clickButton.Parent = mainButton

local glowIntensity = 0.35
local glowDirection = 0.012
local isHovering = false

RunService.RenderStepped:Connect(function()
    if not isHovering then
        glowIntensity = glowIntensity + glowDirection
        if glowIntensity > 0.7 then glowDirection = -0.012 end
        if glowIntensity < 0.3 then glowDirection = 0.012 end
        stroke1.Transparency = 0.55 - (glowIntensity * 0.35)
        stroke2.Transparency = 0.75 - (glowIntensity * 0.25)
        iconStroke.Transparency = 0.5 - (glowIntensity * 0.2)
    end
end)

clickButton.MouseEnter:Connect(function()
    isHovering = true
    PlayHover()
    mainButton:TweenSize(UDim2.new(0, 255, 0, 55), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
    stroke1.Transparency = 0.15
    stroke2.Transparency = 0.35
    stroke1.Thickness = 2.2
    stroke2.Thickness = 4
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    subtitleLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconStroke.Thickness = 1.8
    iconStroke.Transparency = 0.15
end)

clickButton.MouseLeave:Connect(function()
    isHovering = false
    mainButton:TweenSize(UDim2.new(0, 240, 0, 55), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
    stroke1.Thickness = 1.8
    stroke2.Thickness = 3.5
    stroke1.Transparency = 0.55 - (glowIntensity * 0.35)
    stroke2.Transparency = 0.75 - (glowIntensity * 0.25)
    titleLabel.TextColor3 = Color3.fromRGB(245, 245, 255)
    subtitleLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
    iconLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
    iconStroke.Thickness = 1.2
    iconStroke.Transparency = 0.5 - (glowIntensity * 0.2)
end)

clickButton.MouseButton1Click:Connect(function()
    PlayClick(0.5, 1)
    mainButton:TweenSize(UDim2.new(0, 230, 0, 55), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.08, true)
    task.wait(0.08)
    mainButton:TweenSize(UDim2.new(0, 240, 0, 55), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.08, true)
    if _G.VoidWareWindow then
        _G.VoidWareWindow:Toggle()
    end
end)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.T and _G.VoidWareWindow then
        PlayClick(0.45, 1.05)
        _G.VoidWareWindow:Toggle()
    end
end)

local function Notify(content, duration, title)
    WindUI:Notify({
        Title = title or "VoidWare",
        Content = tostring(content),
        Duration = duration or 3,
        Icon = "bell"
    })
end

local function getChar()
    return player.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local CONFIG_PATH = "VoidWare/config.json"
local _config = {}

local function saveConfig()
    pcall(function()
        if not isfolder("VoidWare") then
            makefolder("VoidWare")
        end
        writefile(CONFIG_PATH, HttpService:JSONEncode(_config))
        Notify("Config saved!", 2)
    end)
end

local function loadConfig()
    pcall(function()
        if isfile(CONFIG_PATH) then
            _config = HttpService:JSONDecode(readfile(CONFIG_PATH))
            if _config.DiscordWebhookURL and IsValidWebhook(_config.DiscordWebhookURL) then
                DiscordWebhookURL = _config.DiscordWebhookURL
            end
            if _config.DetectionSystemEnabled ~= nil then
                DetectionSystemEnabled = _config.DetectionSystemEnabled
            end
            if _config.DiscordBotToken then
                DiscordBotToken = _config.DiscordBotToken
            end
            if _config.DiscordChannelId then
                DiscordChannelId = _config.DiscordChannelId
            end
            Notify("Config loaded!", 2)
        else
            Notify("No config found.", 2)
        end
    end)
end

local function setConfig(key, val)
    _config[key] = val
end

local Window = WindUI:CreateWindow({
    Title = "VoidWare v2 [COMPLETE + WEBHOOK + CHAT]",
    Author = "Full Feature Build + Discord Logger + Chat Viewer",
    Folder = "VoidWare",
    Icon = "zap",
    Theme = "Dark",
    Size = UDim2.fromOffset(700, 520),
    Topbar = {
        Height = 44,
        ButtonsType = "Mac"
    }
})

_G.VoidWareWindow = Window

local Tabs = {}
Tabs.Main = Window:Tab({ Title = "Main", Icon = "home" })
Tabs.Player = Window:Tab({ Title = "Player", Icon = "user" })
Tabs.Visuals = Window:Tab({ Title = "Visuals", Icon = "eye" })
Tabs.Fun = Window:Tab({ Title = "Fun", Icon = "smile" })
Tabs.Misc = Window:Tab({ Title = "Misc", Icon = "settings" })
Tabs.Utility = Window:Tab({ Title = "Utility", Icon = "wrench" })
Tabs.Auto = Window:Tab({ Title = "Auto", Icon = "zap" })
Tabs.UI = Window:Tab({ Title = "UI Settings", Icon = "palette" })
Tabs.Discord = Window:Tab({ Title = "Discord Webhooker", Icon = "message-circle" })

-- ==================== DISCORD WEBHOOKER TAB ====================
local DiscordSec = Tabs.Discord:Section({ Title = "Webhook Configuration", Box = true, Opened = true })
local DiscordDetectSec = Tabs.Discord:Section({ Title = "Detection System", Box = true, Opened = true })
local DiscordChatSec = Tabs.Discord:Section({ Title = "View General Chat", Box = true, Opened = true })

local webhookInputValue = ""
local botTokenInputValue = ""
local channelIdInputValue = ""

DiscordSec:Input({
    Flag = "DiscordWebhookURL",
    Title = "Discord Webhook URL",
    PlaceHolder = "Put In Your Discord Webhook Url",
    Callback = function(v)
        webhookInputValue = tostring(v or "")
    end
})

DiscordSec:Button({
    Title = "Apply Discord Webhook",
    Desc = "Save & activate the webhook for logging",
    Callback = function()
        PlayClick()
        if not IsValidWebhook(webhookInputValue) then
            Notify("❌ Invalid Discord webhook URL!", 3)
            return
        end
        DiscordWebhookURL = webhookInputValue
        setConfig("DiscordWebhookURL", DiscordWebhookURL)
        saveConfig()

        local resolved = ResolveChannelFromWebhook()
        if resolved then
            DiscordChannelId = resolved
            setConfig("DiscordChannelId", DiscordChannelId)
            Notify("✅ Webhook applied + Channel ID auto-detected!", 3)
        else
            Notify("✅ Discord Webhook applied successfully!", 3)
        end

        LogCustom("Webhook Applied", "A new Discord webhook was successfully set and saved.", 5763719)
    end
})

DiscordSec:Button({
    Title = "Test",
    Desc = "Send a test embed to your webhook",
    Callback = function()
        PlayClick()
        if not IsValidWebhook(DiscordWebhookURL) then
            Notify("❌ No valid webhook set. Apply one first.", 3)
            return
        end

        local success, err = SendDiscordWebhook({
            username = "VoidWare Logger",
            avatar_url = "https://cdn.discordapp.com/embed/avatars/0.png",
            embeds = {{
                title = "✅ Webhook Test Successful",
                description = "Your Discord webhook is working correctly with VoidWare.",
                color = 5763719,
                fields = {
                    { name = "Player", value = player.Name .. " (`" .. tostring(player.UserId) .. "`)", inline = true },
                    { name = "Executor", value = (identifyexecutor and identifyexecutor()) or "Unknown", inline = true },
                    { name = "Time", value = "<t:" .. tostring(os.time()) .. ":F>", inline = true }
                },
                footer = { text = "VoidWare v2 • Test Message" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        })

        if success then
            Notify("✅ Test message sent to Discord!", 3)
        else
            Notify("❌ Failed to send test: " .. tostring(err), 4)
        end
    end
})

DiscordDetectSec:Toggle({
    Flag = "DetectionSystem",
    Title = "Detection System",
    Desc = "When enabled, every major feature toggle is logged to your Discord webhook",
    Value = false,
    Callback = function(Value)
        DetectionSystemEnabled = Value
        setConfig("DetectionSystemEnabled", Value)
        if Value then PlayToggleOn() else PlayToggleOff() end
        if Value then
            Notify("🔍 Detection System enabled - toggles will be logged", 3)
            LogCustom("Detection System Enabled", "Feature toggle logging is now active.", 5793266)
        else
            Notify("Detection System disabled", 2)
        end
    end
})

DiscordDetectSec:Button({
    Title = "Send Manual Log",
    Desc = "Force send a current status embed",
    Callback = function()
        PlayClick()
        if not IsValidWebhook(DiscordWebhookURL) then
            Notify("No valid webhook set.", 2)
            return
        end
        LogCustom("Manual Status Log", "User requested a manual status report from VoidWare.", 5793266)
        Notify("Manual log sent.", 2)
    end
})

-- ==================== VIEW GENERAL CHAT ====================
DiscordChatSec:Input({
    Flag = "DiscordBotToken",
    Title = "Bot Token (Required to read chat)",
    PlaceHolder = "Paste your Discord Bot Token here",
    Callback = function(v)
        botTokenInputValue = tostring(v or "")
    end
})

DiscordChatSec:Input({
    Flag = "DiscordChannelId",
    Title = "Channel ID (optional - auto from webhook)",
    PlaceHolder = "Leave empty to auto-detect from webhook",
    Callback = function(v)
        channelIdInputValue = tostring(v or "")
    end
})

DiscordChatSec:Button({
    Title = "Apply Bot Token & Channel",
    Desc = "Save token + channel for reading messages",
    Callback = function()
        PlayClick()
        if botTokenInputValue == "" then
            Notify("❌ Bot Token is required to read messages", 3)
            return
        end
        DiscordBotToken = botTokenInputValue
        setConfig("DiscordBotToken", DiscordBotToken)

        if channelIdInputValue ~= "" then
            DiscordChannelId = channelIdInputValue
            setConfig("DiscordChannelId", DiscordChannelId)
            Notify("✅ Bot Token + Channel ID saved!", 3)
        else
            local resolved = ResolveChannelFromWebhook()
            if resolved then
                DiscordChannelId = resolved
                setConfig("DiscordChannelId", DiscordChannelId)
                Notify("✅ Bot Token saved + Channel auto-detected from webhook!", 3)
            else
                Notify("✅ Bot Token saved. Apply a webhook or set Channel ID manually.", 3)
            end
        end
        saveConfig()
    end
})

DiscordChatSec:Button({
    Title = "Fetch Recent Messages",
    Desc = "Pull last 15 messages from the general chat",
    Callback = function()
        PlayClick()
        Notify("Fetching messages from Discord...", 2)

        local success, result = FetchChannelMessages(15)
        if not success then
            Notify("❌ " .. tostring(result), 5)
            return
        end

        if #result == 0 then
            Notify("No messages found in this channel.", 3)
            return
        end

        print("========== VOIDWARE DISCORD CHAT ==========")
        for _, msg in ipairs(result) do
            print("[" .. msg.author .. "]: " .. msg.content)
        end
        print("==========================================")

        local preview = ""
        local count = math.min(6, #result)
        for i = #result - count + 1, #result do
            local msg = result[i]
            local short = string.sub(msg.content, 1, 55)
            if #msg.content > 55 then short = short .. "..." end
            preview = preview .. msg.author .. ": " .. short .. "\n"
        end

        Notify("✅ Fetched " .. #result .. " messages!\n\n" .. preview, 9, "Discord Chat")
    end
})

DiscordChatSec:Toggle({
    Flag = "ChatAutoRefresh",
    Title = "Auto Refresh Chat (every 20s)",
    Desc = "Automatically fetch new messages (uses Bot Token)",
    Value = false,
    Callback = function(Value)
        ChatAutoRefresh = Value
        if Value then PlayToggleOn() else PlayToggleOff() end

        if ChatRefreshThread then
            task.cancel(ChatRefreshThread)
            ChatRefreshThread = nil
        end

        if ChatAutoRefresh then
            Notify("🔄 Auto refresh enabled (every 20 seconds)", 3)
            ChatRefreshThread = task.spawn(function()
                while ChatAutoRefresh do
                    local success, result = FetchChannelMessages(8)
                    if success and #result > 0 then
                        local last = result[#result]
                        print("[VoidWare Chat] " .. last.author .. ": " .. last.content)
                    end
                    task.wait(20)
                end
            end)
        else
            Notify("Auto refresh disabled", 2)
        end
    end
})

DiscordChatSec:Button({
    Title = "Print Last Fetched Messages",
    Desc = "Re-print the last successfully fetched messages to console",
    Callback = function()
        PlayClick()
        if #LastMessages == 0 then
            Notify("No messages cached yet. Click Fetch first.", 3)
            return
        end
        print("========== CACHED DISCORD CHAT ==========")
        for _, msg in ipairs(LastMessages) do
            print("[" .. msg.author .. "]: " .. msg.content)
        end
        print("=========================================")
        Notify("Printed " .. #LastMessages .. " cached messages to console (F9)", 4)
    end
})

-- ==================== MAIN TAB (core movement kept) ====================
local LeftMain = Tabs.Main:Section({ Title = "Movement", Box = true, Opened = true })

local airStrafeEnabled = false
local airStrafeConn = nil
local strafeMult = 120

LeftMain:Toggle({
    Flag = "AirStrafe",
    Title = "Air Strafe Acceleration",
    Desc = "Swing camera in air to gain speed",
    Value = false,
    Callback = function(Value)
        airStrafeEnabled = Value
        if Value then PlayToggleOn() else PlayToggleOff() end
        LogFeature("Air Strafe Acceleration", Value)
        if airStrafeEnabled then
            local camera = workspace.CurrentCamera
            local lastCamLook = camera.CFrame.LookVector
            airStrafeConn = RunService.Heartbeat:Connect(function(dt)
                local hrp = getHRP()
                local hum = getHum()
                if not hrp or not hum then return end
                local currentLook = camera.CFrame.LookVector
                local delta = math.abs(currentLook.X - lastCamLook.X) + math.abs(currentLook.Z - lastCamLook.Z)
                if hum.FloorMaterial == Enum.Material.Air and delta > 0.0005 then
                    local vel = hrp.AssemblyLinearVelocity
                    local flatLook = Vector3.new(currentLook.X, 0, currentLook.Z).Unit
                    hrp.AssemblyLinearVelocity = Vector3.new(
                        vel.X + (flatLook.X * delta * 8 * strafeMult * 0.01),
                        vel.Y,
                        vel.Z + (flatLook.Z * delta * 8 * strafeMult * 0.01)
                    )
                end
                lastCamLook = currentLook
            end)
        elseif airStrafeConn then
            airStrafeConn:Disconnect()
            airStrafeConn = nil
        end
    end
})

LeftMain:Slider({
    Flag = "StrafeMultiplier",
    Title = "Strafe Multiplier",
    Value = { Min = 10, Max = 300, Default = 120 },
    Step = 1,
    Callback = function(v) strafeMult = v end
})

player.CharacterAdded:Connect(function()
    Notify("Character respawned!", 2)
    LogCustom("Character Respawned", "Player character has respawned.", 5793266)
end)

loadConfig()

Notify("🌑 VoidWare v2 [COMPLETE + WEBHOOK + CHAT VIEWER] loaded! Press T to toggle.", 5)
LogCustom("VoidWare Loaded", "Script successfully loaded.\nDetection System: " .. (DetectionSystemEnabled and "ON" or "OFF"), 5793266)
