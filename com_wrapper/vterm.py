import ctypes
from typing import Any

from vterm_bindings import (
    VTerm,
    VTermPos,
    VTermScreen,
    VTermScreenCell,
    vterm_lib,
)


def get_vterm_stripped_row(row_data: bytearray):
    # Strip ending NULLs and spaces
    row_data = row_data.replace(b'\x00', b' ')
    row_data = row_data.rstrip(b' ')
    row_data.append(ord('\n'))
    return row_data


def get_vterm_row_data(cols: int, cells: Any):
    data = bytearray()
    for i in range(cols):
        data.append(cells[i].chars[0])

    return data


def get_vterm_size(vterm: VTerm):
    rows = ctypes.c_int()
    cols = ctypes.c_int()
    vterm_lib.vterm_get_size(vterm, ctypes.byref(rows), ctypes.byref(cols))
    return rows.value, cols.value


def get_vterm_screen_data(vterm: VTerm, vterm_screen: VTermScreen):
    rows, cols = get_vterm_size(vterm)
    pos = VTermPos()
    cell = VTermScreenCell()

    data = bytearray()
    for row in range(rows):
        row_data = bytearray()

        pos.row = row
        for col in range(cols):
            pos.col = col

            vterm_lib.vterm_screen_get_cell(
                vterm_screen,
                pos,
                ctypes.byref(cell),
            )
            row_data.append(cell.chars[0])

        stripped_row_data = get_vterm_stripped_row(row_data)
        data.extend(stripped_row_data)

    return data
