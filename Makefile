CC ?= gcc
CFLAGS ?= -std=c99 -Wall -Wextra -O2 -fPIC
VLC_PLUGIN_CFLAGS ?= $(shell pkg-config --cflags vlc-plugin 2>/dev/null || echo -I/usr/include/vlc -I/usr/include/vlc/plugins)
VLC_PLUGIN_LIBS ?= $(shell pkg-config --libs vlc-plugin 2>/dev/null || echo -lvlccore)

TARGET = libtimestamp_writer_plugin.so
SRCS = src/timestamp_writer.c

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) -shared $(VLC_PLUGIN_CFLAGS) -D__PLUGIN__ -D_FILE_OFFSET_BITS=64 -D__LIBVLC__ -o $@ $^ $(VLC_PLUGIN_LIBS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -d /usr/lib/vlc/plugins/control/
	install -m 755 $(TARGET) /usr/lib/vlc/plugins/control/

.PHONY: all clean install
