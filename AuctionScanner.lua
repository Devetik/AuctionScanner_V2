local MyAddon = CreateFrame("Frame", "AuctionScanner")

-- Table pour stocker les paramètres persistants
if not AuctionScannerDB then
    AuctionScannerDB = {
        targetItemName = "Elemental Earth",
        maxPrice = 7.00 * 10000,
        minStackSize = 2,
        ignoredAuctions = {},
        sortDescending = false -- Direction du tri
    }
end

-- S'assurer que tous les champs existent
AuctionScannerDB.targetItemName = AuctionScannerDB.targetItemName or "Elemental Earth"
AuctionScannerDB.maxPrice = AuctionScannerDB.maxPrice or (7.00 * 10000)
AuctionScannerDB.minStackSize = AuctionScannerDB.minStackSize or 2
AuctionScannerDB.ignoredAuctions = AuctionScannerDB.ignoredAuctions or {}
AuctionScannerDB.sortDescending = AuctionScannerDB.sortDescending or false

-- Variables pour configurer l'objet recherché
local targetItemName = AuctionScannerDB.targetItemName
local maxPrice = AuctionScannerDB.maxPrice
local minStackSize = AuctionScannerDB.minStackSize
local continuousScanTicker = nil -- Variable pour stocker le ticker continu
local awaitingPurchase = false -- Indique si une enchère est en attente d'achat
local isSorting = false -- Drapeau pour éviter la récursion dans le tri
local hasSortedThisSession = false -- Variable pour suivre si le tri a déjà été appliqué

-- Fenêtre pour afficher les résultats
local resultWindow = nil
-- Fenêtre de configuration
local configWindow = nil

-- Création des événements
MyAddon:RegisterEvent("ADDON_LOADED")
MyAddon:RegisterEvent("AUCTION_HOUSE_SHOW")
MyAddon:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
MyAddon:RegisterEvent("AUCTION_HOUSE_CLOSED")

local function printMessage(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MyAuctionScanner]:|r " .. message)
end

-- Fonction pour formater le prix avec les icônes de monnaie
local function formatPrice(price)
    local gold = math.floor(price)
    local silver = math.floor((price - gold) * 100)
    local copper = math.floor(((price - gold) * 100 - silver) * 100)
    return string.format("%d|cffffd700|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t|r %d|cffc7c7cf|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t|r %d|cffeda55f|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t|r", gold, silver, copper)
end

local function createResultWindow()
    if not resultWindow then
        resultWindow = CreateFrame("Frame", "ResultWindow", UIParent, "BasicFrameTemplateWithInset")
        resultWindow:SetSize(400, 200)
        resultWindow:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
        resultWindow:Hide()

        -- Ajout du gestionnaire d'événement pour la fermeture
        resultWindow:SetScript("OnHide", function()
            awaitingPurchase = false
            -- Ne redémarre plus automatiquement le scan
            if configWindow and configWindow.scanButton then
                configWindow.scanButton:SetText("Start Scan")
            end
        end)

        resultWindow.title = resultWindow:CreateFontString(nil, "OVERLAY")
        resultWindow.title:SetFontObject("GameFontHighlight")
        resultWindow.title:SetPoint("TOP", resultWindow, "TOP", 0, -10)
        resultWindow.title:SetText("Matching Auction")

        -- Bouton Acheter
        resultWindow.buyButton = CreateFrame("Button", nil, resultWindow, "UIPanelButtonTemplate")
        resultWindow.buyButton:SetSize(120, 40)
        resultWindow.buyButton:SetPoint("BOTTOMLEFT", resultWindow, "BOTTOMLEFT", 10, 10)
        resultWindow.buyButton:SetText("Buy Now")
        resultWindow.buyButton:Show() -- S'assurer que le bouton est visible par défaut

        -- Bouton Ignorer
        resultWindow.ignoreButton = CreateFrame("Button", nil, resultWindow, "UIPanelButtonTemplate")
        resultWindow.ignoreButton:SetSize(120, 40)
        resultWindow.ignoreButton:SetPoint("BOTTOM", resultWindow, "BOTTOM", 0, 10)
        resultWindow.ignoreButton:SetText("Ignorer")
        resultWindow.ignoreButton:Show() -- S'assurer que le bouton est visible par défaut

        -- Bouton Fermer
        resultWindow.closeButton = CreateFrame("Button", nil, resultWindow, "UIPanelButtonTemplate")
        resultWindow.closeButton:SetSize(120, 40)
        resultWindow.closeButton:SetPoint("BOTTOMRIGHT", resultWindow, "BOTTOMRIGHT", -10, 10)
        resultWindow.closeButton:SetText("Fermer")
        resultWindow.closeButton:SetScript("OnClick", function()
            resultWindow:Hide()
            awaitingPurchase = false
            -- Ne redémarre plus automatiquement le scan
            if configWindow and configWindow.scanButton then
                configWindow.scanButton:SetText("Start Scan")
            end
        end)
        resultWindow.closeButton:Show() -- S'assurer que le bouton est visible par défaut
    end
end

local function showResult(name, stackSize, pricePerUnit, buyoutPrice, auctionIndex, seller, timeLeft)
    printMessage(string.format("Auction details: name=%s, stackSize=%d, pricePerUnit=%d, buyoutPrice=%d, auctionIndex=%d, seller=%s, timeLeft=%d", 
        name, stackSize, pricePerUnit, buyoutPrice, auctionIndex, seller or "Unknown", timeLeft))

    local timeLeftText = ""
    if timeLeft == 1 then
        timeLeftText = "Court"
    elseif timeLeft == 2 then
        timeLeftText = "Moyen"
    elseif timeLeft == 3 then
        timeLeftText = "Long"
    elseif timeLeft == 4 then
        timeLeftText = "Très long"
    end

    resultWindow.title:SetText(string.format("%s (x%d)\nVendeur: %s\nTemps restant: %s\nUnit Price: %dg %ds %dc\nTotal: %dg %ds %dc", 
        name,
        stackSize,
        seller or "Inconnu",
        timeLeftText,
        math.floor(pricePerUnit / 10000),
        math.floor((pricePerUnit % 10000) / 100),
        math.floor(pricePerUnit % 100),
        math.floor(buyoutPrice / 10000),
        math.floor((buyoutPrice % 10000) / 100),
        math.floor(buyoutPrice % 100)))

    resultWindow.buyButton:SetScript("OnClick", function()
        printMessage("Buy Now button clicked.")
        printMessage(string.format("Attempting to buy auctionIndex=%d with buyoutPrice=%d", auctionIndex, buyoutPrice))

        PlaceAuctionBid("list", auctionIndex, buyoutPrice)
        printMessage("Purchase successful at buyout price.")

        resultWindow:Hide()
        awaitingPurchase = false
        -- Ne redémarre plus automatiquement le scan
        if configWindow and configWindow.scanButton then
            configWindow.scanButton:SetText("Start Scan")
        end
    end)

    resultWindow.ignoreButton:SetScript("OnClick", function()
        -- S'assurer que ignoredAuctions existe
        if not AuctionScannerDB.ignoredAuctions then
            AuctionScannerDB.ignoredAuctions = {}
        end
        
        -- Créer une clé unique pour cette enchère
        local auctionKey = string.format("%s_%d_%d", name, buyoutPrice, stackSize)
        AuctionScannerDB.ignoredAuctions[auctionKey] = true
        printMessage("Cette enchère a été ignorée.")
        
        resultWindow:Hide()
        awaitingPurchase = false
        -- Redémarrer le scan pour trouver d'autres offres
        MyAddon.startContinuousScan()
    end)

    resultWindow.buyButton:Show()
    resultWindow.ignoreButton:Show()
    resultWindow.closeButton:Show()
    resultWindow:Show()
end

local function stopContinuousScan()
    if continuousScanTicker then
        continuousScanTicker:Cancel()
        continuousScanTicker = nil
    end
end

local function scanFirstPage()
    if awaitingPurchase then
        return
    end

    local numBatchAuctions, totalAuctions = GetNumAuctionItems("list")

    if numBatchAuctions == 0 then
        return
    end

    for i = 1, numBatchAuctions do
        local name, _, stackSize, _, _, _, _, _, _, buyoutPrice, _, _, _, _, owner = GetAuctionItemInfo("list", i)
        local timeLeft = GetAuctionItemTimeLeft("list", i)

        if name and buyoutPrice and buyoutPrice > 0 then
            local pricePerUnit = buyoutPrice / stackSize

            -- Vérifie si l'enchère respecte les critères
            if name == targetItemName and stackSize >= minStackSize and pricePerUnit <= maxPrice then
                -- Vérifie si l'enchère n'est pas dans la liste des ignorées
                local auctionKey = string.format("%s_%d_%d", name, buyoutPrice, stackSize)
                if not (AuctionScannerDB.ignoredAuctions and AuctionScannerDB.ignoredAuctions[auctionKey]) then
                    printMessage(string.format("Found matching auction: %s (x%d) Unit Price: %dg %ds %dc", 
                        name,
                        stackSize,
                        math.floor(pricePerUnit / 10000),
                        math.floor((pricePerUnit % 10000) / 100),
                        math.floor(pricePerUnit % 100)))

                    stopContinuousScan()
                    PlaySound(5274) -- Jouer un son lorsque l'enchère correspondante est trouvée
                    awaitingPurchase = true
                    showResult(name, stackSize, pricePerUnit, buyoutPrice, i, owner, timeLeft)
                    return
                end
            end
        end
    end
end

local function startContinuousScan()
    stopContinuousScan() -- Stop any ongoing scan before starting a new one
    
    -- Faire une première recherche avant de démarrer le ticker
    QueryAuctionItems(targetItemName, nil, nil, 0, nil, nil, false, 0)
    
    continuousScanTicker = C_Timer.NewTicker(1, function()
        QueryAuctionItems(targetItemName, nil, nil, 0, nil, nil, false, 0)
    end)
end
MyAddon.startContinuousScan = startContinuousScan

local function createConfigWindow()
    if not configWindow then
        configWindow = CreateFrame("Frame", "ConfigWindow", UIParent, "BasicFrameTemplateWithInset")
        configWindow:SetSize(210, 250)
        configWindow:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 0, -15)
        configWindow:Hide()

        configWindow.title = configWindow:CreateFontString(nil, "OVERLAY")
        configWindow.title:SetFontObject("GameFontHighlight")
        configWindow.title:SetPoint("TOP", configWindow, "TOP", 0, -10)
        configWindow.title:SetText("Configuration")

        -- Zone de texte pour le nom de l'objet
        configWindow.itemNameEdit = CreateFrame("EditBox", nil, configWindow, "InputBoxTemplate")
        configWindow.itemNameEdit:SetSize(160, 20)
        configWindow.itemNameEdit:SetPoint("TOP", configWindow.title, "BOTTOM", 0, -20)
        configWindow.itemNameEdit:SetAutoFocus(false)
        configWindow.itemNameEdit:SetText(AuctionScannerDB.targetItemName)
        configWindow.itemNameEdit:SetScript("OnTextChanged", function(self)
            local text = self:GetText()
            AuctionScannerDB.targetItemName = text
            targetItemName = text
        end)
        configWindow.itemNameEdit:SetScript("OnEditFocusLost", function(self)
            self:ClearFocus()
        end)
        
        -- Ajout des fonctionnalités de glisser-déposer et Shift+Click
        configWindow.itemNameEdit:SetScript("OnReceiveDrag", function(self)
            local itemType, itemID, itemLink = GetCursorInfo()
            if itemType == "item" then
                local itemName = GetItemInfo(itemID)
                if itemName then
                    self:SetText(itemName)
                    AuctionScannerDB.targetItemName = itemName
                    targetItemName = itemName
                    ClearCursor()
                end
            end
        end)
        
        configWindow.itemNameEdit:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and IsShiftKeyDown() then
                local itemType, itemID, itemLink = GetCursorInfo()
                if itemType == "item" then
                    local itemName = GetItemInfo(itemID)
                    if itemName then
                        self:SetText(itemName)
                        AuctionScannerDB.targetItemName = itemName
                        targetItemName = itemName
                        ClearCursor()
                    end
                end
            end
        end)
        
        -- Ajout d'un texte d'aide
        configWindow.helpText = configWindow:CreateFontString(nil, "OVERLAY")
        configWindow.helpText:SetFontObject("GameFontNormalSmall")
        configWindow.helpText:SetPoint("TOP", configWindow.itemNameEdit, "BOTTOM", 0, -5)
        configWindow.helpText:SetText("Glissez un objet ou Shift+Click")

        -- Zone de texte pour le prix maximum
        configWindow.priceEdit = CreateFrame("EditBox", nil, configWindow, "InputBoxTemplate")
        configWindow.priceEdit:SetSize(100, 20)
        configWindow.priceEdit:SetPoint("TOPLEFT", configWindow.itemNameEdit, "BOTTOMLEFT", 0, -20)
        configWindow.priceEdit:SetAutoFocus(false)
        configWindow.priceEdit:SetText(tostring(AuctionScannerDB.maxPrice/10000))
        configWindow.priceEdit:SetScript("OnTextChanged", function(self)
            local price = tonumber(self:GetText())
            if price then
                AuctionScannerDB.maxPrice = price * 10000
                maxPrice = price * 10000
                -- Mettre à jour le texte formaté
                configWindow.priceText:SetText(formatPrice(price))
            end
        end)
        configWindow.priceEdit:SetScript("OnEditFocusLost", function(self)
            self:ClearFocus()
        end)

        -- Texte formaté pour afficher le prix avec les icônes
        configWindow.priceText = configWindow:CreateFontString(nil, "OVERLAY")
        configWindow.priceText:SetFontObject("GameFontNormal")
        configWindow.priceText:SetPoint("LEFT", configWindow.priceEdit, "RIGHT", 5, 0)
        configWindow.priceText:SetText(formatPrice(AuctionScannerDB.maxPrice/10000))

        -- Zone de texte pour la quantité minimum
        configWindow.stackEdit = CreateFrame("EditBox", nil, configWindow, "InputBoxTemplate")
        configWindow.stackEdit:SetSize(100, 20)
        configWindow.stackEdit:SetPoint("TOPLEFT", configWindow.priceEdit, "BOTTOMLEFT", 0, -10)
        configWindow.stackEdit:SetAutoFocus(false)
        configWindow.stackEdit:SetText(tostring(AuctionScannerDB.minStackSize))
        configWindow.stackEdit:SetScript("OnTextChanged", function(self)
            local stack = tonumber(self:GetText())
            if stack then
                AuctionScannerDB.minStackSize = stack
                minStackSize = stack
            end
        end)
        configWindow.stackEdit:SetScript("OnEditFocusLost", function(self)
            self:ClearFocus()
        end)

        -- Bouton pour démarrer/arrêter le scan
        configWindow.scanButton = CreateFrame("Button", nil, configWindow, "UIPanelButtonTemplate")
        configWindow.scanButton:SetSize(160, 25)
        configWindow.scanButton:SetPoint("BOTTOM", configWindow, "BOTTOM", 0, 10)
        configWindow.scanButton:SetText("Start Scan")
        configWindow.scanButton:SetScript("OnClick", function()
            if continuousScanTicker then
                stopContinuousScan()
                configWindow.scanButton:SetText("Start Scan")
            else
                printMessage("Starting continuous scan for " .. targetItemName .. "...")
                createResultWindow()
                startContinuousScan()
                configWindow.scanButton:SetText("Stop Scan")
            end
        end)

        -- Bouton pour appliquer les changements
        configWindow.applyButton = CreateFrame("Button", nil, configWindow, "UIPanelButtonTemplate")
        configWindow.applyButton:SetSize(160, 25)
        configWindow.applyButton:SetPoint("BOTTOM", configWindow.scanButton, "TOP", 0, 5)
        configWindow.applyButton:SetText("Appliquer")
        configWindow.applyButton:SetScript("OnClick", function()
            -- Forcer la perte de focus sur tous les champs
            configWindow.itemNameEdit:ClearFocus()
            configWindow.itemNameEdit:SetText(configWindow.itemNameEdit:GetText())
            configWindow.priceEdit:ClearFocus()
            configWindow.priceEdit:SetText(configWindow.priceEdit:GetText())
            configWindow.stackEdit:ClearFocus()
            configWindow.stackEdit:SetText(configWindow.stackEdit:GetText())
            
            -- Forcer la perte de focus en cachant et montrant la fenêtre
            configWindow:Hide()
            C_Timer.After(0.1, function()
                configWindow:Show()
            end)
            
            printMessage(string.format(
                "Configuration mise à jour: '%s' sous %dg %ds par unité avec taille de pile >= %d",
                AuctionScannerDB.targetItemName,
                math.floor(AuctionScannerDB.maxPrice / 10000),
                math.floor((AuctionScannerDB.maxPrice % 10000) / 100),
                AuctionScannerDB.minStackSize
            ))
        end)
    end
end

local function setupUI()
    createConfigWindow()
    configWindow:Show()
    
    -- Mettre à jour le texte du bouton en fonction de l'état du scan
    if configWindow.scanButton then
        if continuousScanTicker then
            configWindow.scanButton:SetText("Stop Scan")
        else
            configWindow.scanButton:SetText("Start Scan")
        end
    end
end

local function onEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == "MyAddon" then
        -- Charger les valeurs sauvegardées
        targetItemName = AuctionScannerDB.targetItemName
        maxPrice = AuctionScannerDB.maxPrice
        minStackSize = AuctionScannerDB.minStackSize
        hasSortedThisSession = false -- Réinitialiser le flag au chargement de l'addon

        SLASH_MYADDON1 = "/setscan"

        SlashCmdList["MYADDON"] = function(msg)
            local name, price, stack = string.match(msg, "^(%S+) (%d+) (%d+)")
            if name and price and stack then
                targetItemName = name
                maxPrice = tonumber(price)
                minStackSize = tonumber(stack)
                printMessage(string.format(
                    "Configured: Searching for '%s' under %dg %ds per unit with stack size >= %d",
                    targetItemName,
                    maxPrice / 10000,
                    minStackSize
                ))
            else
                printMessage("Usage: /setscan [itemName] [maxPrice] [minStackSize]")
            end
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        setupUI()
        -- Trier une seule fois par session
        if not hasSortedThisSession then
            C_Timer.After(0.5, function()
                SortAuctionItems("list", "unitprice")
                hasSortedThisSession = true
            end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        stopContinuousScan()
        if configWindow then
            configWindow:Hide()
        end
        -- Réinitialiser la liste des enchères ignorées
        AuctionScannerDB.ignoredAuctions = {}
        printMessage("Liste des enchères ignorées réinitialisée")
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        scanFirstPage()
    end
end

MyAddon:SetScript("OnEvent", onEvent)
