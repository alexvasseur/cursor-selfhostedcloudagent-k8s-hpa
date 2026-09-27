/* Big cursor ring + click flash for demo recordings (X11). */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/cursorfont.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <math.h>

static Display *dpy;
static Window root, overlay;
static GC gc_ring, gc_flash, gc_clear;
static int screen, W, H;
static int flash_until_ms = 0;
static int flash_x = 0, flash_y = 0;
static Colormap cmap;

static int now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void draw_circle(GC gc, int cx, int cy, int r, int thick) {
  for (int t = 0; t < thick; t++) {
    XDrawArc(dpy, overlay, gc, cx - r - t, cy - r - t, 2 * (r + t), 2 * (r + t), 0, 360 * 64);
  }
}

static void redraw(int mx, int my) {
  XClearWindow(dpy, overlay);
  /* Always-on large ring around pointer so cursor is obvious */
  draw_circle(gc_ring, mx, my, 28, 4);
  draw_circle(gc_ring, mx, my, 8, 2);
  if (now_ms() < flash_until_ms) {
    draw_circle(gc_flash, flash_x, flash_y, 55, 6);
    draw_circle(gc_flash, flash_x, flash_y, 30, 4);
  }
  XFlush(dpy);
}

int main(void) {
  dpy = XOpenDisplay(NULL);
  if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
  screen = DefaultScreen(dpy);
  root = RootWindow(dpy, screen);
  W = DisplayWidth(dpy, screen);
  H = DisplayHeight(dpy, screen);
  cmap = DefaultColormap(dpy, screen);

  XSetWindowAttributes swa;
  memset(&swa, 0, sizeof(swa));
  swa.override_redirect = True;
  swa.background_pixel = 0; /* black; we use Shape? keep simple: use xor or colored bg with no fill */
  /* Use InputOutput with black bg and set background to None via pixmap — simpler: use a
     colored overlay only for rings drawn on black, and make black the "transparent" key via
     XShapeCombineMask if available. Without Xext shape, draw on a full-screen window that
     is NOT pass-through. So we MUST use XShape or XFixes region, or grab won't work under
     the overlay.
     Prefer: select for raw motion on root via XQueryPointer polling and draw with
     XCreateWindow + shape from Xfixes — check for shape extension. */

  /* Approach: no full-screen grab. Use a small follow-window (120x120) that tracks the mouse
     and repositions itself. Clicks still go through because the window is small and we
     raise it after events... Actually small window still steals clicks if under cursor.
     Best: XFixesCreateRegionFromBitmap / ShapeBounding — use XShapeCombineRectangles empty
     then add? Or InputOnly root listener + XDrawRectangle on root (no persist).
     Simplest demo approach that works under x11grab: draw ON THE ROOT with GXxor so it
     inverts pixels; polling loop; flash on button via XQueryPointer mask. No overlay window. */

  GC gc = XCreateGC(dpy, root, 0, NULL);
  XColor yellow, red, exact;
  XAllocNamedColor(dpy, cmap, "yellow", &yellow, &exact);
  XAllocNamedColor(dpy, cmap, "red", &red, &exact);

  XGCValues gcv;
  gcv.function = GXxor;
  gcv.foreground = yellow.pixel;
  gcv.line_width = 4;
  gcv.subwindow_mode = IncludeInferiors;
  GC gcY = XCreateGC(dpy, root, GCFunction|GCForeground|GCLineWidth|GCSubwindowMode, &gcv);
  gcv.foreground = red.pixel;
  gcv.line_width = 6;
  GC gcR = XCreateGC(dpy, root, GCFunction|GCForeground|GCLineWidth|GCSubwindowMode, &gcv);

  /* Also set a very visible system cursor */
  Cursor big = XCreateFontCursor(dpy, XC_crosshair);
  XDefineCursor(dpy, root, big);

  int lx = -1, ly = -1;
  int flash_on = 0;
  int fx = 0, fy = 0;
  int last_btn = 0;
  fprintf(stderr, "click-highlight running (xor rings + crosshair). pid=%d\n", getpid());

  while (1) {
    Window rr, cr;
    int rx, ry, wx, wy;
    unsigned int mask;
    XQueryPointer(dpy, root, &rr, &cr, &rx, &ry, &wx, &wy, &mask);
    int btn = (mask & Button1Mask) ? 1 : 0;

    /* erase old */
    if (lx >= 0) {
      XDrawArc(dpy, root, gcY, lx - 28, ly - 28, 56, 56, 0, 360 * 64);
      XDrawArc(dpy, root, gcY, lx - 10, ly - 10, 20, 20, 0, 360 * 64);
      if (flash_on) {
        XDrawArc(dpy, root, gcR, fx - 55, fy - 55, 110, 110, 0, 360 * 64);
        XDrawArc(dpy, root, gcR, fx - 30, fy - 30, 60, 60, 0, 360 * 64);
      }
    }

    if (btn && !last_btn) {
      flash_on = 12; /* ~12 frames @ 50Hz ≈ 240ms visible pulses */
      fx = rx; fy = ry;
      fprintf(stderr, "CLICK %d %d\n", rx, ry);
    }
    last_btn = btn;
    if (flash_on > 0) flash_on--;

    /* draw new */
    XDrawArc(dpy, root, gcY, rx - 28, ry - 28, 56, 56, 0, 360 * 64);
    XDrawArc(dpy, root, gcY, rx - 10, ry - 10, 20, 20, 0, 360 * 64);
    if (flash_on) {
      XDrawArc(dpy, root, gcR, fx - 55, fy - 55, 110, 110, 0, 360 * 64);
      XDrawArc(dpy, root, gcR, fx - 30, fy - 30, 60, 60, 0, 360 * 64);
    }
    XFlush(dpy);
    lx = rx; ly = ry;
    usleep(20000); /* 50 Hz */
  }
  return 0;
}
