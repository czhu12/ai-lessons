"""A virtual keyboard in ~25 lines: create a uinput device, press Super+7, and remove the device again.

Runs inside the VM as the desktop user (in the wheel group, which may open /dev/uinput). The same calls as
computer_use/uinput.py, without the mouse.
"""
import fcntl, os, struct, time

EV_SYN, EV_KEY = 0x00, 0x01
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x405C5503, 0x5501, 0x5502
KEY_LEFTMETA, KEY_7 = 125, 8   # Super is "left meta" to the kernel; key codes are physical keys, not characters

fd = os.open("/dev/uinput", os.O_WRONLY)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)                      # this device sends key events...
for code in (KEY_LEFTMETA, KEY_7):
    fcntl.ioctl(fd, UI_SET_KEYBIT, code)                   # ...for these two keys
fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x06, 0x1, 0x1, 1, b"lab-keyboard", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)                             # a new keyboard appears in /dev/input
time.sleep(1)                                              # give Hyprland a moment to notice it

def event(type_, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, type_, code, value))   # struct input_event
    os.write(fd, struct.pack("llHHi", 0, 0, EV_SYN, 0, 0))         # "that's one report"

for code, value in [(KEY_LEFTMETA, 1), (KEY_7, 1), (KEY_7, 0), (KEY_LEFTMETA, 0)]:   # 1 = down, 0 = up
    event(EV_KEY, code, value)
time.sleep(0.5)
fcntl.ioctl(fd, UI_DEV_DESTROY)
print("pressed Super+7 on lab-keyboard")
