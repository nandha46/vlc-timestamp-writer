# vlc-timestamp-writer
VLC Extension (Lua) & Native C Interface Plugin to mark start and end timestamps of a video to export as clips in MKVToolNix.

---

## Why Use the Native C Version? (Advantages)

| Advantage | Details |
| :--- | :--- |
| **Microsecond Precision & Zero Overhead** | Reads playback position directly in native machine code without Lua runtime interpreter overhead or garbage collection pauses. |
| **Seamless On-Screen Display (OSD)** | Renders real-time visual feedback (`START: ...`, `END: ...`) directly onto the VLC video rendering surface (`vout_OSDMessage`). |
| **No Window Clutter** | Runs completely headless in the background without needing a separate dialog window floating over the video. |
| **Thread-Safe by Design** | Uses native VLC mutexes (`vlc_mutex_t`) ensuring safe access during seeking, playback rate changes, or fast-forwarding. |
| **Deep Core Integration** | Integrates directly with VLC's `libvlccore` interface engine and action dispatch system. |

---

## 1. Native VLC C/C++ Plugin Module

Source code: [src/timestamp_writer.c](file:///c:/Users/nandh/Downloads/Projects/Lua/vlc-timestamp-writer/src/timestamp_writer.c)

### Compilation Instructions

#### Windows (using MSYS2 MinGW 64-bit):
1. Open the **MSYS2 MINGW64** terminal from your Start Menu.
2. Install the required build tools and VLC development package:
   ```bash
   pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-vlc mingw-w64-x86_64-make
   ```
3. Navigate to this repository:
   ```bash
   cd /c/Users/nandh/Downloads/Projects/Lua/vlc-timestamp-writer
   ```
4. Compile the plugin DLL:
   ```bash
   gcc -std=c99 -shared -fPIC \
       $(pkg-config --cflags vlc-plugin) \
       -D__PLUGIN__ -D_FILE_OFFSET_BITS=64 -D__LIBVLC__ \
       -o libtimestamp_writer_plugin.dll \
       src/timestamp_writer.c \
       $(pkg-config --libs vlc-plugin)
   ```

#### Linux (Debian / Ubuntu / Arch / Fedora):
1. Install development dependencies:
   ```bash
   # Debian / Ubuntu
   sudo apt-get install libvlccore-dev libvlc-dev build-essential
   
   # Arch Linux
   sudo pacman -S vlc base-devel
   ```
2. Build with make:
   ```bash
   make
   ```

---

### Installation & Setup

1. **Copy the compiled library to VLC's plugin directory:**
   - **Windows:** Copy `libtimestamp_writer_plugin.dll` to:
     ```
     C:\Program Files\VideoLAN\VLC\plugins\control\
     ```
   - **Linux:** Copy `libtimestamp_writer_plugin.so` to:
     ```
     /usr/lib/vlc/plugins/control/
     ```
     *(or run `sudo make install`)*

2. **Reset VLC's Plugin Cache:**
   - **Windows (Command Prompt / PowerShell):**
     ```powershell
     & "C:\Program Files\VideoLAN\VLC\vlc.exe" --reset-plugins-cache
     ```
   - **Linux:**
     ```bash
     vlc-cache-gen /usr/lib/vlc/plugins
     ```

---

### How to Use the C Plugin

1. **Enable the Interface in VLC:**
   - Open VLC and go to **Tools > Preferences** (<kbd>Ctrl</kbd> + <kbd>P</kbd>).
   - In the bottom left, switch **Show settings** from *Simple* to **All**.
   - Navigate to **Interface > Control interfaces**.
   - Check the box for **Timestamp Writer** (or add `timestamp_writer` under extra interface modules) and click **Save**.
   - Restart VLC.

2. **Marking Timestamps During Playback:**
   - **Start Segment**: Triggers `key-action-timestamp-start` → Displays `START: HH:MM:SS.mmm` on video OSD.
   - **End Segment**: Triggers `key-action-timestamp-end` → Displays `END: HH:MM:SS.mmm` on video OSD and logs the segment.
   - **Save Log**: Triggers `key-action-timestamp-save` → Writes the MKVToolNix split string format into `<video_name>.txt` in the same directory as the media.

---

## 2. Lua Extension (Script Mode)

If you prefer a lightweight, zero-compilation approach with a graphical dialog window:

### Installation
Copy [timestamp_writer.lua](file:///c:/Users/nandh/Downloads/Projects/Lua/vlc-timestamp-writer/timestamp_writer.lua) into the VLC Lua extensions directory:
- **Windows (all users)**: `%ProgramFiles%\VideoLAN\VLC\lua\extensions\`
- **Windows (current user)**: `%APPDATA%\vlc\lua\extensions\`
- **Linux (all users)**: `/usr/lib/vlc/lua/extensions/`
- **Linux (current user)**: `~/.local/share/vlc/lua/extensions/`
- **macOS**: `/Applications/VLC.app/Contents/MacOS/share/lua/extensions/`

### Usage
- Restart VLC and open a media file.
- Go to the menu: `View > Timestamp writer`.
- Use the **Start Segment**, **End Segment**, and **Save Log and Reset** buttons (or <kbd>Shift</kbd>+<kbd>S</kbd> / <kbd>Shift</kbd>+<kbd>E</kbd>).

