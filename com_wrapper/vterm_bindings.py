import ctypes
from ctypes.util import find_library


class VTermPos(ctypes.Structure):
    _fields_ = [
        ('row', ctypes.c_int),
        ('col', ctypes.c_int),
    ]


class VTermScreenCellAttrs(ctypes.Structure):
    _fields_ = [
        ('bold', ctypes.c_uint, 1),
        ('underline', ctypes.c_uint, 2),
        ('italic', ctypes.c_uint, 1),
        ('blink', ctypes.c_uint, 1),
        ('reverse', ctypes.c_uint, 1),
        ('conceal', ctypes.c_uint, 1),
        ('strike', ctypes.c_uint, 1),
        ('font', ctypes.c_uint, 4),
        ('dwl', ctypes.c_uint, 1),
        ('dhl', ctypes.c_uint, 2),
        ('small', ctypes.c_uint, 1),
        ('baseline', ctypes.c_uint, 2),
    ]


class VTermColorRGB(ctypes.Structure):
    _fields_ = [
        ('type', ctypes.c_uint8),
        ('red', ctypes.c_uint8),
        ('green', ctypes.c_uint8),
        ('blue', ctypes.c_uint8),
    ]


class VTermColorIndexed(ctypes.Structure):
    _fields_ = [
        ('type', ctypes.c_uint8),
        ('idx', ctypes.c_uint8),
    ]


class VTermColor(ctypes.Union):
    _fields_ = [
        ('type', ctypes.c_uint8),
        ('rgb', VTermColorRGB),
        ('indexed', VTermColorIndexed),
    ]


VTERM_MAX_CHARS_PER_CELL = 6


class VTermScreenCell(ctypes.Structure):
    _fields_ = [
        ('chars', ctypes.c_uint32 * VTERM_MAX_CHARS_PER_CELL),
        ('width', ctypes.c_char),
        ('attrs', VTermScreenCellAttrs),
        ('fg', VTermColor),
        ('bg', VTermColor),
    ]


SBPushLineCB = ctypes.CFUNCTYPE(
    ctypes.c_int, ctypes.c_int, ctypes.POINTER(VTermScreenCell), ctypes.c_void_p
)


class VTermScreenCallbacks(ctypes.Structure):
    _fields_ = [
        ('damage', ctypes.c_void_p),
        ('moverect', ctypes.c_void_p),
        ('movecursor', ctypes.c_void_p),
        ('settermprop', ctypes.c_void_p),
        ('bell', ctypes.c_void_p),
        ('resize', ctypes.c_void_p),
        ('sb_pushline', SBPushLineCB),
        ('sb_popline', ctypes.c_void_p),
        ('sb_clear', ctypes.c_void_p),
    ]


VTerm = ctypes.c_void_p
VTermState = ctypes.c_void_p
VTermScreen = ctypes.c_void_p

vterm_lib = ctypes.CDLL(find_library('vterm') or 'libvterm.so')

vterm_lib.vterm_new.argtypes = (ctypes.c_int, ctypes.c_int)
vterm_lib.vterm_new.restype = VTerm

vterm_lib.vterm_obtain_screen.argtypes = (VTerm,)
vterm_lib.vterm_obtain_screen.restype = VTermScreen

vterm_lib.vterm_free.argtypes = (VTerm,)
vterm_lib.vterm_free.restype = None

vterm_lib.vterm_screen_reset.argtypes = (VTermScreen, ctypes.c_int)
vterm_lib.vterm_screen_reset.restype = None


vterm_lib.vterm_screen_set_callbacks.argtypes = (
    VTermScreen,
    ctypes.POINTER(VTermScreenCallbacks),
    ctypes.c_void_p,
)
vterm_lib.vterm_screen_set_callbacks.restype = None

vterm_lib.vterm_input_write.argtypes = (
    VTerm,
    ctypes.c_char_p,
    ctypes.c_size_t,
)
vterm_lib.vterm_input_write.restype = ctypes.c_size_t

vterm_lib.vterm_screen_get_cell.argtypes = (
    VTermScreen,
    VTermPos,
    ctypes.POINTER(VTermScreenCell),
)
vterm_lib.vterm_screen_get_cell.restype = ctypes.c_int

vterm_lib.vterm_set_size.argtypes = (
    VTerm,
    ctypes.c_int,
    ctypes.c_int,
)
vterm_lib.vterm_set_size.restype = None

vterm_lib.vterm_get_size.argtypes = (
    VTerm,
    ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_int),
)
vterm_lib.vterm_get_size.restype = None

# print(f'VTermPos: {ctypes.sizeof(VTermPos)}')
# print(f'VTermScreenCellAttrs: {ctypes.sizeof(VTermScreenCellAttrs)}')
# print(f'VTermColorRGB: {ctypes.sizeof(VTermColorRGB)}')
# print(f'VTermColorIndexed: {ctypes.sizeof(VTermColorIndexed)}')
# print(f'VTermColor: {ctypes.sizeof(VTermColor)}')
# print(f'VTermScreenCell: {ctypes.sizeof(VTermScreenCell)}')
# print(f'VTermScreenCallbacks: {ctypes.sizeof(VTermScreenCallbacks)}')
