#include <stdio.h>
#include <stdlib.h>
#include <vterm.h>

#define ROWS 20
#define COLS 500

static int on_sb_pushline(int cols, const VTermScreenCell* cells, void* user) {
    FILE* out = (FILE*)user;

    int last_nonspace = cols - 1;
    while (last_nonspace >= 0) {
        if (cells[last_nonspace].chars[0] != 0 && cells[last_nonspace].chars[0] != ' ') break;
        last_nonspace--;
    }

    for (int i = 0; i <= last_nonspace; i++) {
        char c = cells[i].chars[0] ? cells[i].chars[0] : ' ';
        putc(c, out);
    }

    putc('\n', out);
    return 1;
}

int main(void) {
    VTerm* vt = vterm_new(ROWS, COLS);
    VTermScreen* screen = vterm_obtain_screen(vt);
    vterm_screen_reset(screen, 1);

    FILE* out = stdout;
    VTermScreenCallbacks cb = {0};
    cb.sb_pushline = on_sb_pushline;
    vterm_screen_set_callbacks(screen, &cb, out);

    char buf[4096];
    size_t len;
    while ((len = fread(buf, 1, sizeof(buf), stdin)) > 0) vterm_input_write(vt, buf, len);

    VTermPos pos;
    VTermScreenCell cells[COLS];
    for (pos.row = 0; pos.row < ROWS; pos.row++) {
        for (pos.col = 0; pos.col < COLS; pos.col++) {
            if (!vterm_screen_get_cell(screen, pos, &cells[pos.col])) cells[pos.col].chars[0] = ' ';
        }
        on_sb_pushline(COLS, cells, out);
    }

    vterm_free(vt);
    return 0;
}
