# vlc-timestamp-writer
VLC Extension to mark start and end timestamps of a video to export as clips in mkvtoolnix

## Overview
With this extension, you can mark segments of a video and export start and end timestamps to a txt file in the same folder. 

## Installation
Download the script file and place it into the special folders in the VLC install directory. Below are the install directories for VLC scripts on different platforms.
 - Windows (all users): %ProgramFiles%\VideoLAN\VLC\lua\
 - Windows (current user): %APPDATA%\VLC\lua\
 - Linux (all users): /usr/lib/vlc/lua/
 - Linux (current user): ~/.local/share/vlc/lua/
 - Mac OS X (all users): /Applications/VLC.app/Contents/MacOS/share/lua/
 - Mac OS X (current user): /Users/%your_name%/Library/Application Support/org.videolan.vlc/lua/


## Usage

 - Restart the vlc after placing the script in one of the above folders.
 - Open a video or audio file
 - Click on the menu `View > Bookmarks` or `VLC > Extension > Bookmarks` on Mac OS X

 ## Roadmap
 
 - add multiple language support
 - support network stream file
 - option to customize export file format
 - test on linux installation