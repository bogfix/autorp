require('lib.moonloader')
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

-- Константы
local CONFIG_FILE = getWorkingDirectory() .. '/config/[AUTORP].json'
local MAX_CMD_SIZE = 64
local MAX_DESC_SIZE = 128
local MAX_STEPS_SIZE = 2048
local AUTHOR = '[18]White_Gasparov [bfix]'
local SCRIPT_VERSION = "1.1"

local VERSION_URL = "https://raw.githubusercontent.com/bogfix/autorp/main/version.json"

-- Глобальные переменные
local renderWindow = imgui.new.bool(false)
local newRP = {
    cmd = imgui.new.char[MAX_CMD_SIZE](),
    desc = imgui.new.char[MAX_DESC_SIZE](),
    steps = imgui.new.char[MAX_STEPS_SIZE]()
}
local editRP = {
    cmd = imgui.new.char[MAX_CMD_SIZE](),
    desc = imgui.new.char[MAX_DESC_SIZE](),
    steps = imgui.new.char[MAX_STEPS_SIZE]()
}
local selectedCommand = imgui.new.int(0)
local commands = {
    {cmd = 'arp', desc = 'Показать список команд для отыгровок'},
    {cmd = 'arpadd', desc = 'Добавить новую отыгровку'},
    {cmd = 'arpupd', desc = 'Обновление скрипта до актуальной версии (если неактуальная)'},
}
local roleplays = {}

-- Утилитные функции
local function decodeString(buffer)
    return u8:decode(ffi.string(buffer))
end

local function splitSteps(stepsString)
    local steps = {}
    for step in stepsString:gmatch("[^\r\n]+") do
        table.insert(steps, u8(step))
    end
    return steps
end

local function showMessage(text, color)
    sampAddChatMessage('[AUTORP] ' .. text, color or -1)
end
-- Работа с конфигурацией
local function saveConfig()
    local success, encoded = pcall(encodeJson, roleplays, { indent = true })
    if not success then
        showMessage("Ошибка кодирования конфигурации!", 0xFF0000)
        return
    end

    local file = io.open(CONFIG_FILE, 'w')
    if file then
        file:write(encoded)
        file:close()
    else
        showMessage("Ошибка записи конфигурации!", 0xFF0000)
    end
end

local function loadConfig()
    if not doesFileExist(CONFIG_FILE) then
        saveConfig()
        return
    end

    local file = io.open(CONFIG_FILE, 'r')
    if not file then
        showMessage("Не удалось открыть файл конфигурации!", 0xFF0000)
        return
    end

    local content = file:read('*a')
    file:close()

    local success, data = pcall(decodeJson, content)
    if success and type(data) == "table" then
        roleplays = data
    else
        showMessage("Ошибка загрузки конфигурации!", 0xFF0000)
    end
end

-- Работа с командами
local function commandExists(cmd)
    for _, rp in ipairs(roleplays) do
        if rp.cmd == cmd then return true end
    end
    return false
end

local function showCommands()
    showMessage('Доступные команды для отыгровок:')
    for _, v in ipairs(commands) do
        showMessage('/' .. v.cmd .. ' - ' .. v.desc)
    end
    for _, v in ipairs(roleplays) do
        showMessage('/' .. v.cmd .. ' - ' .. v.desc)
    end
end

local function registerRoleplayCommand(rp)
    sampRegisterChatCommand(rp.cmd, function()
        lua_thread.create(function()
            for _, step in ipairs(rp.steps) do
                sampSendChat(u8:decode(step))
                wait(1000)
            end
            showMessage('ЗАКОНЧИЛ ОТЫГРОВКУ РП', 0xFF0000)
        end)
    end)
end

local function addNewRoleplay()
    local cmd = decodeString(newRP.cmd)
    local desc = decodeString(newRP.desc)
    local stepsString = decodeString(newRP.steps)
    local steps = splitSteps(stepsString)

    if cmd == '' or desc == '' or #steps == 0 then
        showMessage('Ошибка: заполните все поля для добавления отыгровки.', 0xFF0000)
        return
    end

    if commandExists(cmd) then
        showMessage('Ошибка: команда с таким именем уже существует.', 0xFF0000)
        newRP.cmd = imgui.new.char[MAX_CMD_SIZE]()
        return
    end

    local rp = {cmd = cmd, desc = desc, steps = steps}
    table.insert(roleplays, rp)
    registerRoleplayCommand(rp)
    showMessage('Новая отыгровка добавлена: /' .. cmd)
    saveConfig()
    newRP = {
        cmd = imgui.new.char[MAX_CMD_SIZE](),
        desc = imgui.new.char[MAX_DESC_SIZE](),
        steps = imgui.new.char[MAX_STEPS_SIZE]()
    }
end

local function importConfig(filePath)
    local file = io.open(filePath, 'r')
    if not file then
        showMessage('Ошибка: файл не найден.', 0xFF0000)
        return
    end

    local content = file:read('*a')
    file:close()

    local success, importedData = pcall(decodeJson, content)
    if not success or type(importedData) ~= "table" then
        showMessage('Ошибка: файл поврежден или имеет неверный формат.', 0xFF0000)
        return
    end

    for _, importedRP in ipairs(importedData) do
        if not commandExists(importedRP.cmd) then
            table.insert(roleplays, importedRP)
            registerRoleplayCommand(importedRP)
        end
    end

    saveConfig()
    showMessage('Конфигурация успешно импортирована.')
end

function update()
    local raw = VERSION_URL
    local dlstatus = require('moonloader').download_status
    local requests = require('requests')
    local f = {}
    function f:getLastVersion()
        local response = requests.get(raw)
        if response.status_code == 200 then
            return decodeJson(response.text)['last']
        else
            return 'UNKNOWN'
        end
    end
    function f:download()
        local response = requests.get(raw)
        if response.status_code == 200 then
            downloadUrlToFile(decodeJson(response.text)['url'], thisScript().path, function (id, status, p1, p2)
                print('Скачиваю '..decodeJson(response.text)['url']..' в '..thisScript().path)
                if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                    showMessage('Скрипт обновлен, перезагрузка...', -1)
                    thisScript():reload()
                end
            end)
        else
            showMessage('Ошибка, невозможно установить обновление, код: '..response.status_code, -1)
        end
    end
    return f
end

-- Основная функция
function main()
    while not isSampAvailable() do wait(0) end
    local lastver = update():getLastVersion()
    loadConfig()
    sampRegisterChatCommand('arp', showCommands)
    sampRegisterChatCommand('arpadd', function()
        renderWindow[0] = not renderWindow[0]
    end)

    for _, rp in ipairs(roleplays) do
        registerRoleplayCommand(rp)
    end
    if sampIsLocalPlayerSpawned() then
        if SCRIPT_VERSION ~= lastver then
            sampRegisterChatCommand('arpupd', function()
                update():download()
            end)
            showMessage('Вышло обновление скрипта ('..SCRIPT_VERSION..' -> '..lastver..'), введите /arpupd для обновления!', 0xfcba03)
        end
    end
    showMessage('{ffffff}Успешно загружен {363636}[Список команд - /arp | Создание команд - /arpadd] {FFFFFF}| Версия - '..SCRIPT_VERSION, 0x33ff33)
    wait(-1)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    theme()
end)

imgui.OnFrame(
    function() return renderWindow[0] end,
    function()
        local resX, resY = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(800, 600), imgui.Cond.FirstUseEver)

        if imgui.Begin(u8'Управление отыгровками', renderWindow) then
            if imgui.BeginTabBar('Tabs') then
                if imgui.BeginTabItem(u8'Информация') then
                    imgui.CText(u8'Добро пожаловать в скрипт AutoRP!')
                    imgui.Separator()
                    imgui.CText(u8'Автор: '.. AUTHOR)
                    imgui.CText(u8'Версия: ' .. SCRIPT_VERSION)
                    imgui.CText(u8'Дата создания: 01.03.2025')
                    imgui.Separator()
                    imgui.CText(u8'Инструкция:')
                    imgui.BulletText(u8'Используйте /arp для просмотра списка команд.')
                    imgui.BulletText(u8'Добавляйте новые отыгровки во вкладке "Добавить новую отыгровку".')
                    imgui.BulletText(u8'Редактируйте или удаляйте существующие команды во вкладках с их названиями.')
                    imgui.BulletText(u8'Импортируйте конфигурации через кнопку импорта.')
                    imgui.Separator()
                    imgui.CText(u8'Связь с автором [DISCORD]:') 
                    imgui.SameLine()
                    imgui.TextColored(imgui.ImVec4(0, 1, 0, 1), u8'bogfix')
                    local calc = imgui.CalcTextSize(text)
                    imgui.SetCursorPosX((imgui.GetWindowWidth() - calc.x) / 2.5)
                    imgui.Link('https://t.me/jfmc18_bot',u8 'Бот больницы Jefferson [18]')
                    imgui.EndTabItem()
                end
                if imgui.BeginTabItem(u8'Добавить новую отыгровку') then
                    imgui.Text(u8'Введите команду (без /):')
                    imgui.InputText(u8'Команда', newRP.cmd, MAX_CMD_SIZE)
                    imgui.Text(u8'Введите описание:')
                    imgui.InputText(u8'Описание', newRP.desc, MAX_DESC_SIZE)
                    imgui.Text(u8'Добавьте шаги отыгровки (каждая новая строка - новый шаг):')
                    if imgui.Button(u8'Вставить из буфера обмена') then
                        local text = getClipboardText()
                        if text then
                            ffi.copy(newRP.steps, u8(text))
                        else
                            showMessage('Не удалось получить текст из буфера обмена.', 0xFF0000)
                        end
                    end
                    imgui.InputTextMultiline(u8'Шаги', newRP.steps, MAX_STEPS_SIZE, imgui.ImVec2(-1, 200))
                    if imgui.Button(u8'Добавить отыгровку') then
                        addNewRoleplay()
                    end
                    if imgui.Button(u8'Импортировать команды (Выберите файл "[AUTORP].json")') then
                        local status, path = FileDialog(false, nil, getWorkingDirectory())
                        if status then
                            if path:find('.json$') then
                                if path == CONFIG_FILE then
                                    showMessage('{ffffff}Ты шо бессмертный, выбери тот который ты скачал а не тот что у тебя уже есть.', 0x33ff33)
                                else
                                    showMessage('{ffffff}Загружаю конфигурацию...', 0x33ff33)
                                    importConfig(path)
                                end
                            else
                                showMessage('{ffffff}Файл не является конфигом скрипта! {2b2a2a}[ Он должен иметь формат {FF0000}.json{2b2a2a} ]', 0x33ff33)
                            end
                        else
                            showMessage('{ffffff}Вы не выбрали файл!', 0x33ff33)
                        end
                    end
                    imgui.EndTabItem()
                end

                for i, rp in ipairs(roleplays) do
                    if imgui.BeginTabItem(u8'/' .. rp.cmd) then
                        selectedCommand[0] = i
                        if selectedCommand[0] == i then
                            ffi.copy(editRP.cmd, u8(rp.cmd))
                            ffi.copy(editRP.desc, u8(rp.desc))
                            ffi.copy(editRP.steps, table.concat(rp.steps, "\n"))
                        end

                        imgui.Text(u8'Команда:')
                        if imgui.InputText(u8'##cmd' .. i, editRP.cmd, MAX_CMD_SIZE) then
                            rp.cmd = decodeString(editRP.cmd)
                        end
                        imgui.Text(u8'Описание:')
                        if imgui.InputText(u8'##desc' .. i, editRP.desc, MAX_DESC_SIZE) then
                            rp.desc = decodeString(editRP.desc)
                        end
                        imgui.Text(u8'Шаги:')
                        if imgui.InputTextMultiline(u8'##steps' .. i, editRP.steps, MAX_STEPS_SIZE, imgui.ImVec2(-1, 200)) then
                            rp.steps = splitSteps(decodeString(editRP.steps))
                        end

                        if imgui.Button(u8'Сохранить изменения') then
                            saveConfig()
                            showMessage('Отыгровка /' .. rp.cmd .. ' успешно изменена.')
                        end
                        if imgui.Button(u8'Удалить отыгровку') then
                            table.remove(roleplays, i)
                            saveConfig()
                            showMessage('Отыгровка /' .. rp.cmd .. ' удалена.')
                            selectedCommand[0] = 0
                        end
                        imgui.EndTabItem()
                    end
                end
                imgui.EndTabBar()
            end
            imgui.End()
        end
    end
)
function theme() -- Chapo loh
    imgui.SwitchContext()
    --==[ STYLE ]==--
    imgui.GetStyle().WindowPadding = imgui.ImVec2(5, 5)
    imgui.GetStyle().FramePadding = imgui.ImVec2(5, 5)
    imgui.GetStyle().ItemSpacing = imgui.ImVec2(5, 5)
    imgui.GetStyle().ItemInnerSpacing = imgui.ImVec2(2, 2)
    imgui.GetStyle().TouchExtraPadding = imgui.ImVec2(0, 0)
    imgui.GetStyle().IndentSpacing = 0
    imgui.GetStyle().ScrollbarSize = 10
    imgui.GetStyle().GrabMinSize = 10

    --==[ BORDER ]==--
    imgui.GetStyle().WindowBorderSize = 1
    imgui.GetStyle().ChildBorderSize = 1
    imgui.GetStyle().PopupBorderSize = 1
    imgui.GetStyle().FrameBorderSize = 1
    imgui.GetStyle().TabBorderSize = 1

    --==[ ROUNDING ]==--
    imgui.GetStyle().WindowRounding = 5
    imgui.GetStyle().ChildRounding = 5
    imgui.GetStyle().FrameRounding = 5
    imgui.GetStyle().PopupRounding = 5
    imgui.GetStyle().ScrollbarRounding = 5
    imgui.GetStyle().GrabRounding = 5
    imgui.GetStyle().TabRounding = 5

    --==[ ALIGN ]==--
    imgui.GetStyle().WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    imgui.GetStyle().ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
    imgui.GetStyle().SelectableTextAlign = imgui.ImVec2(0.5, 0.5)
    
    --==[ COLORS ]==--
    imgui.GetStyle().Colors[imgui.Col.Text]                   = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
    imgui.GetStyle().Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
    imgui.GetStyle().Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
    imgui.GetStyle().Colors[imgui.Col.Border]                 = imgui.ImVec4(0.25, 0.25, 0.26, 0.54)
    imgui.GetStyle().Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    imgui.GetStyle().Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.25, 0.25, 0.26, 1.00)
    imgui.GetStyle().Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.25, 0.25, 0.26, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.00, 0.00, 0.00, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.41, 0.41, 0.41, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.51, 0.51, 0.51, 1.00)
    imgui.GetStyle().Colors[imgui.Col.CheckMark]              = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
    imgui.GetStyle().Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.21, 0.20, 0.20, 1.00)
    imgui.GetStyle().Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.21, 0.20, 0.20, 1.00)
    imgui.GetStyle().Colors[imgui.Col.Button]                 = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.21, 0.20, 0.20, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.41, 0.41, 0.41, 1.00)
    imgui.GetStyle().Colors[imgui.Col.Header]                 = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
    imgui.GetStyle().Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.47, 0.47, 0.47, 1.00)
    imgui.GetStyle().Colors[imgui.Col.Separator]              = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(1.00, 1.00, 1.00, 0.25)
    imgui.GetStyle().Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(1.00, 1.00, 1.00, 0.67)
    imgui.GetStyle().Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(1.00, 1.00, 1.00, 0.95)
    imgui.GetStyle().Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.28, 0.28, 0.28, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TabUnfocused]           = imgui.ImVec4(0.07, 0.10, 0.15, 0.97)
    imgui.GetStyle().Colors[imgui.Col.TabUnfocusedActive]     = imgui.ImVec4(0.14, 0.26, 0.42, 1.00)
    imgui.GetStyle().Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.61, 0.61, 0.61, 1.00)
    imgui.GetStyle().Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(1.00, 0.43, 0.35, 1.00)
    imgui.GetStyle().Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.90, 0.70, 0.00, 1.00)
    imgui.GetStyle().Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(1.00, 0.60, 0.00, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(1.00, 0.00, 0.00, 0.35)
    imgui.GetStyle().Colors[imgui.Col.DragDropTarget]         = imgui.ImVec4(1.00, 1.00, 0.00, 0.90)
    imgui.GetStyle().Colors[imgui.Col.NavHighlight]           = imgui.ImVec4(0.26, 0.59, 0.98, 1.00)
    imgui.GetStyle().Colors[imgui.Col.NavWindowingHighlight]  = imgui.ImVec4(1.00, 1.00, 1.00, 0.70)
    imgui.GetStyle().Colors[imgui.Col.NavWindowingDimBg]      = imgui.ImVec4(0.80, 0.80, 0.80, 0.20)
    imgui.GetStyle().Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.00, 0.00, 0.00, 0.70)
end

function imgui.CText(text)
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX((imgui.GetWindowWidth() - calc.x) / 2)
    imgui.Text(text)
end

function imgui.Link(link, text)
	text = text or link
	local tSize = imgui.CalcTextSize(text)
	local p = imgui.GetCursorScreenPos()
	local DL = imgui.GetWindowDrawList()
	local col = { 0xFFFF7700, 0xFFFF9900 }
	if imgui.InvisibleButton('##' .. link, tSize) then os.execute('explorer ' .. link) end
	local color = imgui.IsItemHovered() and col[1] or col[2]
	DL:AddText(p, color, text)
	DL:AddLine(imgui.ImVec2(p.x, p.y + tSize.y), imgui.ImVec2(p.x + tSize.x, p.y + tSize.y), color)
end

-- Open FileManager
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef([[
    static const int OFN_FILEMUSTEXIST  = 0x1000;
    static const int OFN_NOCHANGEDIR    = 8;
    static const int OFN_PATHMUSTEXIST  = 0x800;

    typedef unsigned short WORD;
    typedef unsigned long DWORD;
    typedef const char *LPCSTR;
    typedef char *LPSTR;
    typedef long LPARAM;
    typedef void* HWND;
    typedef void* HINSTANCE;
    typedef void* LPOFNHOOKPROC;

    typedef struct {
        DWORD         lStructSize;
        HWND          hwndOwner;
        HINSTANCE     hInstance;
        LPCSTR        lpstrFilter;
        LPSTR         lpstrCustomFilter;
        DWORD         nMaxCustFilter;
        DWORD         nFilterIndex;
        LPSTR         lpstrFile;
        DWORD         nMaxFile;
        LPSTR         lpstrFileTitle;
        DWORD         nMaxFileTitle;
        LPCSTR        lpstrInitialDir;
        LPCSTR        lpstrTitle;
        DWORD         flags;
        WORD          nFileOffset;
        WORD          nFileExtension;
        LPCSTR        lpstrDefExt;
        LPARAM        lCustData;
        LPOFNHOOKPROC lpfnHook;
        LPCSTR        lpTemplateName;
        void*         pvReserved;
        DWORD         dwReserved;
        DWORD         flagsEx;
    } OPENFILENAME;

    int GetSaveFileNameA(OPENFILENAME *lpofn);
    int GetOpenFileNameA(OPENFILENAME *lpofn);
    DWORD GetLastError(void);
]])

local comdlg32 = ffi.load("comdlg32")
local kernel32 = ffi.load("kernel32")

function FileDialog(saveDialog, fileExtension, defaultDir) --- By Chapo + Upgrades by ChatGPT 4o
    local ofn = ffi.new("OPENFILENAME")
    local fileBuffer = ffi.new("char[260]", "\0")  -- Буфер для пути файла

    ofn.lStructSize = ffi.sizeof(ofn)
    ofn.hwndOwner = nil
    ofn.lpstrFile = fileBuffer
    ofn.nMaxFile = ffi.sizeof(fileBuffer)
    ofn.lpstrFilter = fileExtension
    ofn.nFilterIndex = 1
    ofn.lpstrInitialDir = defaultDir or getGameDirectory()
    ofn.flags = bit.bor(comdlg32.OFN_PATHMUSTEXIST, comdlg32.OFN_FILEMUSTEXIST, comdlg32.OFN_NOCHANGEDIR)

    local result = saveDialog and comdlg32.GetSaveFileNameA(ofn) or comdlg32.GetOpenFileNameA(ofn)
    if result ~= 0 then
        return true, ffi.string(ofn.lpstrFile)
    else
        local errorCode = kernel32.GetLastError()
        return false, errorCode == 0 and "Отмена пользователем" or ("Ошибка: " .. errorCode)
    end
end