/**
 * @file timestamp_writer.c
 * @brief Native VLC Interface/Control Module for Timestamp Marking & MKVToolNix Export
 *
 * Author: Nandhakumar Subramanian
 *
 * This module allows users to mark segment start/end timestamps during video playback
 * and saves MKVToolNix split-compatible timestamps to a .txt file alongside the media file.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_interface.h>
#include <vlc_input.h>
#include <vlc_vout.h>
#include <vlc_vout_osd.h>
#include <vlc_url.h>
#include <vlc_fs.h>
#include <vlc_playlist.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#define MODULE_STRING "timestamp_writer"
#define OSD_DURATION_US (1200 * 1000) /* 1.2 seconds in microseconds */

/*****************************************************************************
 * Module Descriptor
 *****************************************************************************/
static int  Open (vlc_object_t *);
static void Close(vlc_object_t *);

/* Callbacks for VLC actions / hotkeys */
static int ActionStartSegment(vlc_object_t *, char const *, vlc_value_t, vlc_value_t, void *);
static int ActionEndSegment  (vlc_object_t *, char const *, vlc_value_t, vlc_value_t, void *);
static int ActionSaveLog     (vlc_object_t *, char const *, vlc_value_t, vlc_value_t, void *);

vlc_module_begin()
    set_shortname(N_("Timestamp Writer"))
    set_description(N_("Timestamp Writer for MKVToolNix clip splitting"))
    set_category(CAT_INTERFACE)
    set_subcategory(SUBCAT_INTERFACE_CONTROL)
    set_capability("interface", 0)
    set_callbacks(Open, Close)
vlc_module_end()

/*****************************************************************************
 * Internal State Structure
 *****************************************************************************/
struct intf_sys_t
{
    vlc_mutex_t lock;
    int64_t     i_start_time_us; /* Start timestamp in microseconds (-1 if unset) */
    char       *psz_log_entries; /* Accumulated MKVToolNix split entries */
};

/*****************************************************************************
 * Helpers
 *****************************************************************************/
static void FormatTime(int64_t i_time_us, char *psz_buffer, size_t i_buf_size)
{
    int64_t total_seconds = i_time_us / 1000000;
    int64_t hours         = total_seconds / 3600;
    int64_t minutes       = (total_seconds % 3600) / 60;
    int64_t seconds       = total_seconds % 60;
    int64_t milliseconds = (i_time_us / 1000) % 1000;

    snprintf(psz_buffer, i_buf_size, "%02" PRId64 ":%02" PRId64 ":%02" PRId64 ".%03" PRId64,
             hours, minutes, seconds, milliseconds);
}

static void ShowOSD(intf_thread_t *p_intf, input_thread_t *p_input, const char *psz_msg)
{
    vout_thread_t *p_vout = input_GetVout(p_input);
    if (p_vout != NULL)
    {
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", psz_msg);
        vlc_object_release(p_vout);
    }
    else
    {
        msg_Info(p_intf, "%s", psz_msg);
    }
}

/*****************************************************************************
 * Open: Initialize interface module
 *****************************************************************************/
static int Open(vlc_object_t *p_this)
{
    intf_thread_t *p_intf = (intf_thread_t *)p_this;
    intf_sys_t *p_sys = malloc(sizeof(intf_sys_t));
    if (unlikely(p_sys == NULL))
        return VLC_ENOMEM;

    vlc_mutex_init(&p_sys->lock);
    p_sys->i_start_time_us = -1;
    p_sys->psz_log_entries = strdup("");
    if (!p_sys->psz_log_entries)
    {
        free(p_sys);
        return VLC_ENOMEM;
    }

    p_intf->p_sys = p_sys;

    /* Register custom variable actions on the libvlc instance */
    var_Create(p_intf->obj.libvlc, "key-action-timestamp-start", VLC_VAR_VOID | VLC_VAR_ISCOMMAND);
    var_AddCallback(p_intf->obj.libvlc, "key-action-timestamp-start", ActionStartSegment, p_intf);

    var_Create(p_intf->obj.libvlc, "key-action-timestamp-end", VLC_VAR_VOID | VLC_VAR_ISCOMMAND);
    var_AddCallback(p_intf->obj.libvlc, "key-action-timestamp-end", ActionEndSegment, p_intf);

    var_Create(p_intf->obj.libvlc, "key-action-timestamp-save", VLC_VAR_VOID | VLC_VAR_ISCOMMAND);
    var_AddCallback(p_intf->obj.libvlc, "key-action-timestamp-save", ActionSaveLog, p_intf);

    msg_Info(p_intf, "Timestamp Writer native VLC module initialized");
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Close: Deinitialize interface module
 *****************************************************************************/
static void Close(vlc_object_t *p_this)
{
    intf_thread_t *p_intf = (intf_thread_t *)p_this;
    intf_sys_t *p_sys = p_intf->p_sys;

    var_DelCallback(p_intf->obj.libvlc, "key-action-timestamp-start", ActionStartSegment, p_intf);
    var_Destroy(p_intf->obj.libvlc, "key-action-timestamp-start");

    var_DelCallback(p_intf->obj.libvlc, "key-action-timestamp-end", ActionEndSegment, p_intf);
    var_Destroy(p_intf->obj.libvlc, "key-action-timestamp-end");

    var_DelCallback(p_intf->obj.libvlc, "key-action-timestamp-save", ActionSaveLog, p_intf);
    var_Destroy(p_intf->obj.libvlc, "key-action-timestamp-save");

    vlc_mutex_destroy(&p_sys->lock);
    free(p_sys->psz_log_entries);
    free(p_sys);
}

/*****************************************************************************
 * Start Segment Action Callback
 *****************************************************************************/
static int ActionStartSegment(vlc_object_t *p_this, char const *psz_var,
                              vlc_value_t oldval, vlc_value_t newval, void *p_data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz_var); VLC_UNUSED(oldval); VLC_UNUSED(newval);
    intf_thread_t *p_intf = (intf_thread_t *)p_data;
    intf_sys_t *p_sys = p_intf->p_sys;

    playlist_t *p_playlist = pl_Get(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (!p_input)
    {
        msg_Warn(p_intf, "Timestamp Writer: No active media input");
        return VLC_EGENERIC;
    }

    int64_t i_time_us = var_GetInteger(p_input, "time");

    vlc_mutex_lock(&p_sys->lock);
    p_sys->i_start_time_us = i_time_us;
    vlc_mutex_unlock(&p_sys->lock);

    char sz_time[32];
    FormatTime(i_time_us, sz_time, sizeof(sz_time));

    char sz_osd[64];
    snprintf(sz_osd, sizeof(sz_osd), "START: %s", sz_time);
    ShowOSD(p_intf, p_input, sz_osd);

    msg_Info(p_intf, "Timestamp Writer: Marked START at %s", sz_time);
    vlc_object_release(p_input);
    return VLC_SUCCESS;
}

/*****************************************************************************
 * End Segment Action Callback
 *****************************************************************************/
static int ActionEndSegment(vlc_object_t *p_this, char const *psz_var,
                            vlc_value_t oldval, vlc_value_t newval, void *p_data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz_var); VLC_UNUSED(oldval); VLC_UNUSED(newval);
    intf_thread_t *p_intf = (intf_thread_t *)p_data;
    intf_sys_t *p_sys = p_intf->p_sys;

    playlist_t *p_playlist = pl_Get(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (!p_input)
    {
        msg_Warn(p_intf, "Timestamp Writer: No active media input");
        return VLC_EGENERIC;
    }

    vlc_mutex_lock(&p_sys->lock);
    if (p_sys->i_start_time_us < 0)
    {
        vlc_mutex_unlock(&p_sys->lock);
        ShowOSD(p_intf, p_input, "ERROR: Set Start Segment first!");
        msg_Err(p_intf, "Timestamp Writer: Start segment has not been marked");
        vlc_object_release(p_input);
        return VLC_EGENERIC;
    }

    int64_t i_start_us = p_sys->i_start_time_us;
    int64_t i_end_us = var_GetInteger(p_input, "time");

    if (i_end_us < i_start_us)
    {
        vlc_mutex_unlock(&p_sys->lock);
        ShowOSD(p_intf, p_input, "ERROR: End time is before Start time!");
        msg_Err(p_intf, "Timestamp Writer: End time is before Start time");
        vlc_object_release(p_input);
        return VLC_EGENERIC;
    }

    char sz_start[32], sz_end[32];
    FormatTime(i_start_us, sz_start, sizeof(sz_start));
    FormatTime(i_end_us, sz_end, sizeof(sz_end));

    /* Append MKVToolNix format: ",+START-END" */
    size_t new_len = strlen(p_sys->psz_log_entries) + strlen(sz_start) + strlen(sz_end) + 8;
    char *psz_new_log = realloc(p_sys->psz_log_entries, new_len);
    if (psz_new_log)
    {
        p_sys->psz_log_entries = psz_new_log;
        strcat(p_sys->psz_log_entries, ",+");
        strcat(p_sys->psz_log_entries, sz_start);
        strcat(p_sys->psz_log_entries, "-");
        strcat(p_sys->psz_log_entries, sz_end);
    }

    p_sys->i_start_time_us = -1; /* Reset start time */
    vlc_mutex_unlock(&p_sys->lock);

    char sz_osd[64];
    snprintf(sz_osd, sizeof(sz_osd), "END: %s", sz_end);
    ShowOSD(p_intf, p_input, sz_osd);

    msg_Info(p_intf, "Timestamp Writer: Logged Segment %s - %s", sz_start, sz_end);
    vlc_object_release(p_input);
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Save Log Action Callback
 *****************************************************************************/
static int ActionSaveLog(vlc_object_t *p_this, char const *psz_var,
                         vlc_value_t oldval, vlc_value_t newval, void *p_data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz_var); VLC_UNUSED(oldval); VLC_UNUSED(newval);
    intf_thread_t *p_intf = (intf_thread_t *)p_data;
    intf_sys_t *p_sys = p_intf->p_sys;

    playlist_t *p_playlist = pl_Get(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (!p_input)
    {
        msg_Warn(p_intf, "Timestamp Writer: No active media input to resolve path");
        return VLC_EGENERIC;
    }

    input_item_t *p_item = input_GetItem(p_input);
    if (!p_item || !p_item->psz_uri)
    {
        vlc_object_release(p_input);
        return VLC_EGENERIC;
    }

    char *psz_path = vlc_uri2path(p_item->psz_uri);
    if (!psz_path)
    {
        ShowOSD(p_intf, p_input, "ERROR: Must play a local file to save log");
        msg_Err(p_intf, "Timestamp Writer: Current item is not a local file");
        vlc_object_release(p_input);
        return VLC_EGENERIC;
    }

    vlc_mutex_lock(&p_sys->lock);
    if (strlen(p_sys->psz_log_entries) == 0)
    {
        vlc_mutex_unlock(&p_sys->lock);
        ShowOSD(p_intf, p_input, "No segments logged yet");
        free(psz_path);
        vlc_object_release(p_input);
        return VLC_SUCCESS;
    }

    /* Build output filename by replacing/appending extension with .txt */
    char sz_output_path[1024];
    char *psz_dot = strrchr(psz_path, '.');
    char *psz_sep = strrchr(psz_path, '/');
#ifdef _WIN32
    char *psz_win_sep = strrchr(psz_path, '\\');
    if (psz_win_sep && (!psz_sep || psz_win_sep > psz_sep))
        psz_sep = psz_win_sep;
#endif

    if (psz_dot && (!psz_sep || psz_dot > psz_sep))
    {
        size_t base_len = psz_dot - psz_path;
        snprintf(sz_output_path, sizeof(sz_output_path), "%.*s.txt", (int)base_len, psz_path);
    }
    else
    {
        snprintf(sz_output_path, sizeof(sz_output_path), "%s.txt", psz_path);
    }

    /* Skip leading ",+" (first 2 chars) matching Lua logic */
    const char *psz_content = p_sys->psz_log_entries;
    if (strncmp(psz_content, ",+", 2) == 0)
        psz_content += 2;
    else if (psz_content[0] == ',')
        psz_content += 1;

    FILE *f = vlc_fopen(sz_output_path, "w");
    if (f)
    {
        fputs(psz_content, f);
        fclose(f);

        ShowOSD(p_intf, p_input, "Log saved successfully!");
        msg_Info(p_intf, "Timestamp Writer: Log saved to %s", sz_output_path);

        /* Reset entries */
        p_sys->psz_log_entries[0] = '\0';
        p_sys->i_start_time_us = -1;
    }
    else
    {
        ShowOSD(p_intf, p_input, "ERROR: Could not open file for writing");
        msg_Err(p_intf, "Timestamp Writer: Failed to write file %s", sz_output_path);
    }

    vlc_mutex_unlock(&p_sys->lock);
    free(psz_path);
    vlc_object_release(p_input);
    return VLC_SUCCESS;
}
