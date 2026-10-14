-- OurTibia login theme is bundled for a later audio-backend-safe hook.
-- The custom OGG is kept in the package, but playback stays disabled here because
-- this client build crashes inside the native audio decoder during startup.
local musicFilename = 'sounds/1098/ourtibia_theme'
local musicChannel = nil

function setMusic(filename)
    musicFilename = filename
end

function startup()
    local errtitle = nil
    local errmsg = nil
    if g_graphics.getRenderer():lower():match('gdi generic') then
        errtitle = tr('Graphics card driver not detected')
        errmsg = tr('No graphics card detected, everything will be drawn using the CPU, thus the performance will be really bad. Please update your graphics driver to have a better performance.')
    end
    if errmsg or errtitle then
        local msgbox = displayErrorBox(errtitle, errmsg)
        msgbox.onOk = function() EnterGame.firstShow() end
    else
        EnterGame.firstShow()
    end
    if g_app.hasUpdater() and g_sounds then
        g_sounds.setAudioEnabled(g_settings.getBoolean('enableAudio'))
    end
end

function init()
    if g_app.hasUpdater() then
        connect(g_app, {onUpdateFinished = startup})
    else
        connect(g_app, {onRun = startup})
    end
end

function terminate()
    if g_app.hasUpdater() then
        disconnect(g_app, {onUpdateFinished = startup})
    else
        disconnect(g_app, {onRun = startup})
    end
end
