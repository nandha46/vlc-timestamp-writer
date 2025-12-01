local start_time_ms = nil
local log_entries = ""
local segment_dialog
local osd_duration = 1200

function descriptor()
    return {
        title = "Timestamp writer",
        version = "0.0.1",
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

local function start_segment()
	local input_object = vlc.object.input()
	local current_time_microseconds = vlc.var.get(input_object, "time")
	start_time_ms = current_time_microseconds / 1000	
    local formatted_time = format_time(start_time_ms)
	segment_dialog:add_label("START:" .. formatted_time .. "\n")
	
	vlc.osd.message("START:" .. formatted_time .. "\n", osd_duration)
end

local function end_segment()
    if start_time_ms == nil then
        segment_dialog:add_label("ERROR: Click 'Start Segment' first!")
        return
    end
    
	local input_object = vlc.object.input()
	local current_time_microseconds = vlc.var.get(input_object, "time")
	local end_time_ms = current_time_microseconds / 1000
    
    if end_time_ms < start_time_ms then
        segment_dialog:add_label("ERROR: End time is before Start time!")
        return
    end

    local formatted_start = format_time(start_time_ms)
    local formatted_end = format_time(end_time_ms)
    
	vlc.osd.message("END:"..formatted_end.."\n", osd_duration)

    log_entries = log_entries .. ",+" .. formatted_start .. "-" .. formatted_end
    
    start_time_ms = nil
    
    local segment_count = #log_entries:gsub("[^%+]","") 
    segment_dialog:add_label(string.format("Segment #%d Logged:\n%s - %s\nReady for next segment or click 'Save Log'.", segment_count, formatted_start, formatted_end))
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
        log_entries = ""
    end
	
	vlc.delete_key("Start Segment Mark")
    vlc.delete_key("End Segment Mark")
	
end