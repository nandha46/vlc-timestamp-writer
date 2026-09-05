local start_time_ms = nil
local log_entries = ""
local segment_dialog
local osd_duration = 1200

function descriptor()
    return {
        title = "Timestamp writer",
        version = "0.0.2",
        author = "Nandhakumar Subramanian",
        shortdesc = "Timestamp writer",
        description = "VLC Extension to mark start and end timestamps of a video to export as clips in mkvtoolnix",
        capabilities = {"view:togglebutton"},
        url = "https://github.com/nandha46/vlc-timestamp-writer"
    }
end

local function format_time(time_ms)
    local time_seconds = time_ms / 1000
    local hours = math.floor(time_seconds / 3600)
    local minutes = math.floor((time_seconds % 3600) / 60)
    local seconds = math.floor(time_seconds % 60)
    local milliseconds = time_ms % 1000
    
    return string.format("%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
end

local last_segment_start_ms = nil
local last_segment_end_ms = nil

local function start_segment()
	local input_object = vlc.object.input()
	local current_time_microseconds = vlc.var.get(input_object, "time")
	start_time_ms = current_time_microseconds / 1000	
    local formatted_time = format_time(start_time_ms)
	
    if last_segment_start_ms ~= nil and last_segment_end_ms == nil then
        segment_dialog:add_label("START updated: " .. formatted_time .. "\n")
        vlc.osd.message("START (Updated): " .. formatted_time .. "\n", osd_duration)
    else
        segment_dialog:add_label("START: " .. formatted_time .. "\n")
        vlc.osd.message("START: " .. formatted_time .. "\n", osd_duration)
    end

    last_segment_start_ms = start_time_ms
    last_segment_end_ms = nil
end

local function end_segment()
    local input_object = vlc.object.input()
    local current_time_microseconds = vlc.var.get(input_object, "time")
    local current_end_ms = current_time_microseconds / 1000

    -- Case 1: Start segment is currently active (normal end segment or initial completion)
    if start_time_ms ~= nil then
        if current_end_ms < start_time_ms then
            segment_dialog:add_label("ERROR: End time is before Start time!")
            return
        end

        local formatted_start = format_time(start_time_ms)
        local formatted_end = format_time(current_end_ms)
        
        vlc.osd.message("END: " .. formatted_end .. "\n", osd_duration)

        log_entries = log_entries .. ",+" .. formatted_start .. "-" .. formatted_end
        
        last_segment_start_ms = start_time_ms
        last_segment_end_ms = current_end_ms
        start_time_ms = nil
        
        local segment_count = #log_entries:gsub("[^%+]","") 
        segment_dialog:add_label(string.format([[Segment #%d Logged: %s - %s.]], segment_count, formatted_start, formatted_end))
    -- Case 2: No active start segment, but we already have a logged segment -> replace last segment's end time
    elseif last_segment_start_ms ~= nil and last_segment_end_ms ~= nil then
        if current_end_ms < last_segment_start_ms then
            segment_dialog:add_label("ERROR: End time is before Start time!")
            return
        end

        local formatted_start = format_time(last_segment_start_ms)
        local formatted_old_end = format_time(last_segment_end_ms)
        local formatted_new_end = format_time(current_end_ms)

        -- Replace the last logged segment entry ",+<start>-<old_end>" with ",+<start>-<new_end>"
        local pattern = ",%+" .. formatted_start:gsub("%-", "%%-") .. "%-" .. formatted_old_end:gsub("%-", "%%-") .. "$"
        local updated_log, count = log_entries:gsub(pattern, ",+" .. formatted_start .. "-" .. formatted_new_end)
        if count > 0 then
            log_entries = updated_log
        else
            -- Fallback: match whatever last segment is at the end of log_entries
            log_entries = log_entries:gsub(",%+" .. formatted_start:gsub("%-", "%%-") .. "%-[^,]+$", ",+" .. formatted_start .. "-" .. formatted_new_end)
        end

        last_segment_end_ms = current_end_ms
        vlc.osd.message("END (Updated): " .. formatted_new_end .. "\n", osd_duration)

        local segment_count = #log_entries:gsub("[^%+]","") 
        segment_dialog:add_label(string.format([[Segment #%d End Updated: %s - %s.]], segment_count, formatted_start, formatted_new_end))
    else
        segment_dialog:add_label("ERROR: Click 'Start Segment' first!")
        return
    end
end

local function save_log_file()
    if log_entries == "" then
		segment_dialog:add_label("No segments logged yet.")
        return
    end
    
    local media_uri = vlc.input.item():uri()
    
    if not media_uri or media_uri == "" or media_uri:sub(1, 4) ~= "file" then
        segment_dialog:add_label("Error: Must play a local file to save log.")
        return
    end

    local media_path = vlc.strings.decode_uri(media_uri)
    media_path = media_path:gsub("^file:///*", "") 

    local directory, filename 
    
    local last_sep_pos = media_path:match(".+[/\\]")
    if last_sep_pos then
        directory = last_sep_pos
        filename = media_path:sub(#last_sep_pos + 1)
    else
        directory = ""
        filename = media_path
    end

    local base_filename = filename:match("(.+)%.[^%.]+$") or filename
    local output_path = directory .. base_filename .. ".txt"
    
    local file = io.open(output_path, "w")
    
    if file then
        local final_output = log_entries:sub(3) 
        file:write(final_output)
        file:close()
		segment_dialog:add_label("Log Saved.")
    else
        vlc.messages.log(vlc.messages.ERROR, "Could not open file for writing: " .. output_path)
    end
    
    log_entries = ""
    start_time_ms = nil
    last_segment_start_ms = nil
    last_segment_end_ms = nil
    
    segment_dialog:add_label("Log saved successfully! Ready to start new log.")
end

function activate()
    segment_dialog = vlc.dialog("Segment Logger")
    
	segment_dialog:add_label("Ready. Click 'Start Segment' to begin marking a clip.")
	segment_dialog:add_button("Start Segment", start_segment)
	segment_dialog:add_button("End Segment", end_segment)
    segment_dialog:add_label("---")
    segment_dialog:add_button("Save Log and Reset", save_log_file)
    segment_dialog:show(segment_dialog)
	
	vlc.keypressed("s", "Start Segment Mark", start_segment, 
        vlc.key_modifier.Shift, 
        vlc.key_action.Press)

    vlc.keypressed("e", "End Segment Mark", end_segment, 
        vlc.key_modifier.Shift, 
        vlc.key_action.Press)
end

function deactivate()
    if segment_dialog then
        vlc.dialog.hide(segment_dialog)
        segment_dialog = nil
        start_time_ms = nil
        last_segment_start_ms = nil
        last_segment_end_ms = nil
        log_entries = ""
    end
	
	vlc.delete_key("Start Segment Mark")
    vlc.delete_key("End Segment Mark")
	
end