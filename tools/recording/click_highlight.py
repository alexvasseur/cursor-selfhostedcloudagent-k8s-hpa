#!/usr/bin/env python3
import os, sys, time
from Xlib import X, display

dpy = display.Display()
root = dpy.screen().root
cmap = dpy.screen().default_colormap

def alloc(name, fb):
    try: return cmap.alloc_named_color(name).pixel
    except Exception: return fb

yellow = alloc("yellow", dpy.screen().white_pixel)
red = alloc("red", dpy.screen().white_pixel)

def make_gc(fg, width=5):
    return root.create_gc(function=X.GXxor, foreground=fg, line_width=width,
                          subwindow_mode=X.IncludeInferiors)

gcY, gcR = make_gc(yellow, 5), make_gc(red, 7)
print(f"click_highlight pid={os.getpid()} display={os.environ.get('DISPLAY')}", flush=True)

lx=ly=None; flash_left=0; fx=fy=0; last_btn=False

def xor_rings(gc, x, y, ro, ri):
    root.poly_arc(gc, [(x-ro, y-ro, 2*ro, 2*ro, 0, 360*64)])
    root.poly_arc(gc, [(x-ri, y-ri, 2*ri, 2*ri, 0, 360*64)])

while True:
    ptr = root.query_pointer()
    rx, ry = ptr.root_x, ptr.root_y
    btn = bool(ptr.mask & X.Button1Mask)
    if lx is not None:
        xor_rings(gcY, lx, ly, 36, 14)
        if flash_left > 0:
            xor_rings(gcR, fx, fy, 70, 42)
    if btn and not last_btn:
        flash_left = 30; fx, fy = rx, ry
        print(f"CLICK {rx} {ry}", flush=True)
    last_btn = btn
    if flash_left > 0: flash_left -= 1
    xor_rings(gcY, rx, ry, 36, 14)
    if flash_left > 0:
        xor_rings(gcR, fx, fy, 70, 42)
    dpy.flush(); lx, ly = rx, ry; time.sleep(0.01)
