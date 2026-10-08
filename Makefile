AS      = as
LD      = ld
ASFLAGS = -arch arm64
LDFLAGS = -arch arm64 \
          -platform_version macos 12.0 12.0 \
          -e _main \
          -lSystem \
          -L$(shell xcrun --show-sdk-path)/usr/lib

TARGET  = cpuid
OBJ     = cpuid.o
SRC     = cpuid.s

.PHONY: all run clean

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $<

$(OBJ): $(SRC)
	$(AS) $(ASFLAGS) -o $@ $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJ)
