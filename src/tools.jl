include("brush.jl")

eventMouse = Union{Gtk.GdkEventButton, Gtk.GdkEventMotion}
eventKey = Gtk.GdkEventKey

loadedTools = joinpath.("tools", readdir(@abs "tools"))
loadModule.(loadedTools)
currentTool = nothing

mouseHandlers = Dict{Integer, String}(
    1 => "leftClick",
    2 => "middleClick",
    3 => "rightClick",
    4 => "backClick",
    5 => "forwardClick"
)

function getToolName(tool::String)
    if hasModuleField(tool, "displayName")
        return getModuleField(tool, "displayName")

    elseif haskey(loadedModules, tool)
        return repr(loadedModules[tool])
    end
end

toolDisplayNames = Dict{String, String}(
    getToolName(tool) => tool for tool in loadedTools if haskey(loadedModules, tool)
)

subtoolList = generateTreeView("Mode", [])
connectChanged(subtoolList, function(list::ListContainer, selected::String)
    eventToModule(currentTool, "subToolSelected", list, selected)
end)

layersList = generateTreeView("Layer", [])
connectChanged(layersList, function(list::ListContainer, selected::String)
    eventToModule(currentTool, "layerSelected", list, selected)
    eventToModule(currentTool, "layerSelected", list, materialList, selected)
end)

materialList = generateTreeView("Material", [])
connectChanged(materialList, function(list::ListContainer, selected::String)
    eventToModule(currentTool, "materialSelected", list, selected)
end)

function changeTool!(tool::String)
    if loadedMap !== nothing && loadedRoom !== nothing
        dr = getDrawableRoom(loadedMap, loadedRoom)

        if tool in loadedTools
            global currentTool = tool
        
        elseif haskey(toolDisplayNames, tool)
            global currentTool = toolDisplayNames[tool]
        end
        
        # Clear the subtool and material list
        # Tools need to set up this themselves
        updateTreeView!(subtoolList, [])
        updateTreeView!(materialList, [])

        eventToModule(currentTool, "layersChanged", dr.layers)
        eventToModule(currentTool, "toolSelected")
        eventToModule(currentTool, "toolSelected", subtoolList, layersList, materialList)
    end
end

toolList = generateTreeView("Tool", collect(keys(toolDisplayNames)))
connectChanged(toolList, function(list::ListContainer, selected::String)
    debug.log("Selected $selected", "TOOLS_SELECTED")
    changeTool!(selected)
end)

function selectionRectangle(x1::Number, y1::Number, x2::Number, y2::Number)
    drawX = min(x1, x2)
    drawW = abs(x1 - x2) + 1

    drawY = min(y1, y2)
    drawH = abs(y1 - y2) + 1

    return Rectangle(drawX, drawY, drawW, drawH)
end

function updateSelectionByCoords!(map::Map, ax::Number, ay::Number)
    room = Maple.getRoomByCoords(map, ax, ay)

    if room != false && room.name != selectedRoom
        select!(roomList, row -> row[1] == room.name)
    
        return true
    end

    return false
end

function selectMaterialList!(m::String)
    select!(materialList, row -> row[1] == m)
end

function updateLayerList!(layers::Array{Layer, 1}, layer::Union{Layer, Void}, default::String="")
    newLayer = getLayerByName(layers, layerName(layer), default)

    select!(layersList, row -> row[1] == newLayer.name)

    return newLayer
end

function handleSelectionMotion(start::eventMouse, startCamera::Camera, current::eventMouse)
    room = loadedRoom
    
    mx1, my1 = getMapCoordinates(startCamera, start.x, start.y)
    mx2, my2 = getMapCoordinates(camera, current.x, current.y)

    max1, may1 = getMapCoordinatesAbs(startCamera, start.x, start.y)
    max2, may2 = getMapCoordinatesAbs(camera, current.x, current.y)

    x1, y1 = mapToRoomCoordinates(mx1, my1, room)
    x2, y2 = mapToRoomCoordinates(mx2, my2, room)

    ax1, ay1 = mapToRoomCoordinatesAbs(max1, may1, room)
    ax2, ay2 = mapToRoomCoordinatesAbs(max2, may2, room)

    # Grid Based coordinates
    eventToModule(currentTool, "selectionMotion", selectionRectangle(x1, y1, x2, y2))
    eventToModule(currentTool, "selectionMotion", x1, y1, x2, y2)

    # Absolute coordinates
    eventToModule(currentTool, "selectionMotionAbs", selectionRectangle(ax1, ay1, ax2, ay2))
    eventToModule(currentTool, "selectionMotionAbs", ax1, ay1, ax2, ay2)
end

function handleSelectionFinish(start::eventMouse, startCamera::Camera, current::eventMouse)
    room = loadedRoom
    
    mx1, my1 = getMapCoordinates(startCamera, start.x, start.y)
    mx2, my2 = getMapCoordinates(camera, current.x, current.y)

    max1, may1 = getMapCoordinatesAbs(startCamera, start.x, start.y)
    max2, may2 = getMapCoordinatesAbs(camera, current.x, current.y)

    x1, y1 = mapToRoomCoordinates(mx1, my1, room)
    x2, y2 = mapToRoomCoordinates(mx2, my2, room)

    ax1, ay1 = mapToRoomCoordinatesAbs(max1, may1, room)
    ax2, ay2 = mapToRoomCoordinatesAbs(max2, may2, room)

    # Grid Based coordinates
    eventToModule(currentTool, "selectionFinish", selectionRectangle(x1, y1, x2, y2))
    eventToModule(currentTool, "selectionFinish", x1, y1, x2, y2)

    # Absolute coordinates
    eventToModule(currentTool, "selectionFinishAbs", selectionRectangle(ax1, ay1, ax2, ay2))
    eventToModule(currentTool, "selectionFinishAbs", ax1, ay1, ax2, ay2)
end

function handleClicks(event::eventMouse, camera::Camera)
    if haskey(mouseHandlers, event.button)
        handle = mouseHandlers[event.button]
        room = loadedRoom

        mx, my = getMapCoordinates(camera, event.x, event.y)
        max, may = getMapCoordinatesAbs(camera, event.x, event.y)

        x, y = mapToRoomCoordinates(mx, my, room)
        ax, ay = mapToRoomCoordinatesAbs(max, may, room)

        lock!(camera)
        if !updateSelectionByCoords!(loadedMap, max, may)
            # Teleport to cursor 
            if EverestRcon.loaded && event.button == 0x1 && modifierControl() && modifierShift()
                url = get(config, "everest_rcon", "http://localhost:32270")
                room = selectedRoom[5:end]
                EverestRcon.reload(url, room)
                EverestRcon.teleportToRoom(url, room, ax, ay)

            else
                eventToModule(currentTool, handle)
                eventToModule(currentTool, handle, event, camera)
                eventToModule(currentTool, handle, x, y)
                eventToModule(currentTool, handle * "Abs", ax, ay)
            end
        end
        unlock!(camera)
    end
end

function handleMotion(event::eventMouse, camera::Camera)
    room = loadedRoom

    mx, my = getMapCoordinates(camera, event.x, event.y)
    max, may = getMapCoordinatesAbs(camera, event.x, event.y)

    x, y = mapToRoomCoordinates(mx, my, room)
    ax, ay = mapToRoomCoordinatesAbs(max, may, room)

    eventToModule(currentTool, "mouseMotion", event, camera)
    eventToModule(currentTool, "mouseMotion", x, y)
    eventToModule(currentTool, "mouseMotionAbs", event, camera)
    eventToModule(currentTool, "mouseMotionAbs", ax, ay)
end

function handleKeyPressed(event::eventKey)
    if get(debug.config, "ENABLE_HOTSWAP_HOTKEYS", false)
        # F1 Key
        # Reload tools
        if event.keyval == Gtk.GdkKeySyms.F1
            loadModule.(loadedTools)
            changeTool!(loadedTools[1])
            select!(roomList, row -> row[1] == selectedRoom)
        end

        # F2
        # Reload entity drawing
        if event.keyval == Gtk.GdkKeySyms.F2
            dr = getDrawableRoom(loadedMap, loadedRoom)
            loadModule.(loadedEntities)
            registerPlacements!(entityPlacements, loadedEntities)
            getLayerByName(dr.layers, "entities").redraw = true
            select!(roomList, row -> row[1] == selectedRoom)
        end
    end

    eventToModule(currentTool, "keyboard", event)
end

function handleKeyReleased(event::eventKey)

end

function handleRoomChanged(map::Map, room::Room)
    dr = getDrawableRoom(map, room)

    # Clean up tools layer before notifying about room change
    eventToModule(currentTool, "cleanup")

    eventToModule(currentTool, "roomChanged", room)
    eventToModule(currentTool, "roomChanged", map, room)
    eventToModule(currentTool, "layersChanged", dr.layers)
end