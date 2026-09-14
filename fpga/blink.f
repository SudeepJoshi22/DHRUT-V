# Smoke test for the board and the toolchain: a single LED blinker with no CPU.
# Build this first when a cpu_top bitstream misbehaves -- if blink does not work
# either, the problem is the pins, the clock or the flashing step, not the CPU.
#
# One source per line. '#' starts a WHOLE-LINE comment only: the Makefile strips
# '^\s*#' lines but not trailing ones, so a comment after a filename would be
# handed to the frontend as a filename.
blink.v
