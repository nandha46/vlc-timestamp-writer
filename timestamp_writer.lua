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
local status_label = nil
local history_label = nil
local segment_list = nil

local function refresh_list()
    if not segment_list then return end
    segment_list:clear()
    
    local count = 1
    for start_str, end_str in log_entries:gmatch("%+([%d:%.]+)%-([%d:%.]+)") do
        segment_list:add_value(string.format("Segment #%d: %s ➔ %s", count, start_str, end_str), count)
        count = count + 1
    end
end

local function update_status(html_text)
    if status_label then
        status_label:set_text([[<span style="font-size: 13px;">]] .. html_text .. [[</span><br>]])
    end
end

local function update_history(html_text)
    if history_label then
        history_label:set_text([[<span style="font-size: 13px;">]] .. html_text .. [[</span><br><br>]])
    end
end

local function start_segment()
	local input_object = vlc.object.input()
	local current_time_microseconds = vlc.var.get(input_object, "time")
	start_time_ms = current_time_microseconds / 1000	
    local formatted_time = format_time(start_time_ms)
	
    if last_segment_start_ms ~= nil and last_segment_end_ms == nil then
        update_status(string.format([[<b>Status:</b> <span style="color: #27ae60;">🔄 Start Updated:</span> <b>%s</b>]], formatted_time))
        vlc.osd.message("START (Updated): " .. formatted_time .. "\n", osd_duration)
    else
        update_status(string.format([[<b>Status:</b> <span style="color: #27ae60;">🟢 Start Marked:</span> <b>%s</b>]], formatted_time))
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
            update_status([[<b>Status:</b> <span style="color: #e74c3c;">⚠️ ERROR: End time is before Start time!</span>]])
            return
        end

        local formatted_start = format_time(start_time_ms)
        local formatted_end = format_time(current_end_ms)
        
        vlc.osd.message("END: " .. formatted_end .. "\n", osd_duration)

        log_entries = log_entries .. ",+" .. formatted_start .. "-" .. formatted_end
        refresh_list()
        
        last_segment_start_ms = start_time_ms
        last_segment_end_ms = current_end_ms
        start_time_ms = nil
        
        local segment_count = #log_entries:gsub("[^%+]","") 
        update_status(string.format([[<b>Status:</b> <span style="color: #2980b9;">✅ Segment #%d Logged</span>]], segment_count))
        update_history(string.format([[<b>Last Segment:</b> %s ➔ %s]], formatted_start, formatted_end))
    -- Case 2: No active start segment, but we already have a logged segment -> replace last segment's end time
    elseif last_segment_start_ms ~= nil and last_segment_end_ms ~= nil then
        if current_end_ms < last_segment_start_ms then
            update_status([[<b>Status:</b> <span style="color: #e74c3c;">⚠️ ERROR: End time is before Start time!</span>]])
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
        refresh_list()

        last_segment_end_ms = current_end_ms
        vlc.osd.message("END (Updated): " .. formatted_new_end .. "\n", osd_duration)

        local segment_count = #log_entries:gsub("[^%+]","") 
        update_status(string.format([[<b>Status:</b> <span style="color: #e67e22;">🔄 Segment #%d End Updated</span>]], segment_count))
        update_history(string.format([[<b>Last Segment:</b> %s ➔ %s]], formatted_start, formatted_new_end))
    else
        update_status([[<b>Status:</b> <span style="color: #e74c3c;">⚠️ ERROR: Click 'Start Segment' first!</span>]])
        return
    end
end

local function parse_time_to_ms(time_str)
    local h, m, s, ms = time_str:match("(%d+):(%d+):(%d+)%.(%d+)")
    if h and m and s and ms then
        return (tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)) * 1000 + tonumber(ms)
    end
    return 0
end

local function calculate_total_duration_ms(entries)
    local total_ms = 0
    for start_str, end_str in entries:gmatch("%+([%d:%.]+)%-([%d:%.]+)") do
        local seg_start = parse_time_to_ms(start_str)
        local seg_end = parse_time_to_ms(end_str)
        if seg_end > seg_start then
            total_ms = total_ms + (seg_end - seg_start)
        end
    end
    return total_ms
end

local function save_log_file()
    if log_entries == "" then
		update_status([[<b>Status:</b> <span style="color: #7f8c8d;">No segments logged yet.</span>]])
        return
    end
    
    local media_uri = vlc.input.item():uri()
    
    if not media_uri or media_uri == "" or media_uri:sub(1, 4) ~= "file" then
        update_status([[<b>Status:</b> <span style="color: #e74c3c;">⚠️ Error: Must play a local file to save.</span>]])
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
    
    local total_duration_ms = calculate_total_duration_ms(log_entries)
    local formatted_duration = format_time(total_duration_ms)
    local segment_count = #log_entries:gsub("[^%+]","") 

    local file = io.open(output_path, "w")
    
    if file then
        local final_output = log_entries:sub(3) 
        file:write(final_output)
        file:close()
        vlc.osd.message("Log Saved! (" .. segment_count .. " segments, Total: " .. formatted_duration .. ")", osd_duration * 2)
        update_status(string.format([[<b>Status:</b> <span style="color: #27ae60;">💾 Saved!</span> <b>%d</b> segments (<b>%s</b>)]], segment_count, formatted_duration))
        update_history([[<b>Saved to:</b> ]] .. base_filename .. ".txt")
    else
        vlc.messages.log(vlc.messages.ERROR, "Could not open file for writing: " .. output_path)
        update_status([[<b>Status:</b> <span style="color: #e74c3c;">⚠️ Could not write file.</span>]])
    end
    
    log_entries = ""
    start_time_ms = nil
    last_segment_start_ms = nil
    last_segment_end_ms = nil
    refresh_list()
end

function activate()
    segment_dialog = vlc.dialog("Timestamp Writer")
    
    -- Row 1: Header Banner (spans full width, sets a generous minimum width using HTML table)
    segment_dialog:add_label([[<table width="450"><tr><td><br><span style="font-size: 15px; font-weight: bold; color: #2c3e50;">🎬 MKVToolNix Segment Writer</span><br></td></tr></table>]], 1, 1, 2, 1)

    -- Row 2: Status Line
    status_label = segment_dialog:add_label([[<span style="font-size: 13px;"><b>Status:</b> <span style="color: #7f8c8d;">Ready to mark clips</span></span><br>]], 1, 2, 2, 1)

    -- Row 3: History / Last segment preview
    history_label = segment_dialog:add_label([[<span style="font-size: 13px;"><b>Last Segment:</b> <i>None</i></span><br><br>]], 1, 3, 2, 1)

    -- Row 4: Grid Action Buttons: Start (Col 1) and End (Col 2)
    segment_dialog:add_button("🟢 ▶ Start Segment", start_segment, 1, 4, 1, 1)
    segment_dialog:add_button("🔴 ⏹ End Segment", end_segment, 2, 4, 1, 1)

    -- Row 5: Segment List
    segment_list = segment_dialog:add_list(1, 5, 2, 1)

    -- Row 6: Separator with vertical breathing room
    segment_dialog:add_label([[<br><hr width="450" color="#d0d7de" /><br>]], 1, 6, 2, 1)

    -- Row 7: Save and Reset button (spans both columns)
    segment_dialog:add_button("💾 Save Log & Reset", save_log_file, 1, 7, 2, 1)

    segment_dialog:show(segment_dialog)
end

function deactivate()
    if segment_dialog then
        vlc.dialog.hide(segment_dialog)
        segment_dialog = nil
        status_label = nil
        history_label = nil
        segment_list = nil
        start_time_ms = nil
        last_segment_start_ms = nil
        last_segment_end_ms = nil
        log_entries = ""
    end
end