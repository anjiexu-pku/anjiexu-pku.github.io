# Asterinas on Milk-V Megrez: Claim Audit

Date: 2026-07-23

## Recommended story

TankTechnology brought Asterinas up on a physical Milk-V Megrez RISC-V board
to an interactive `tty0` BusyBox shell. The controlled integration reused the
U-Boot framebuffer and demonstrated basic local input through the Megrez USB
host path and one boot-time-connected HID Boot Protocol keyboard. The same
RAM-only canary returned to U-Boot through a new firmware cycle.

This is materially stronger than a banner-only or kernel-entry result: the
evidence sequence crosses firmware handoff, early page tables, OSTD and SMP,
rootfs, PID 1, UART TX/RX, framebuffer console, USB host, keyboard input, TTY
line discipline, and shell interaction.

The homepage should describe this as a controlled bring-up milestone, not as
formal board support.

## Calls

- **Support:** A physical Megrez candidate reached an interactive `tty0`
  BusyBox shell.
- **Support:** The controlled run reached a new OpenSBI/U-Boot epoch and ended
  at the U-Boot prompt.
- **Caution:** The keyboard and visible-console conclusion includes operator
  observation. The serial record proves boot and recovery, but cannot capture
  `tty0` keystrokes or screen output.
- **Caution:** The demonstrated keyboard scope is intentionally narrow: one
  boot-time-connected USB HID Boot Protocol keyboard with basic keys.
- **Fail:** There is no basis for calling this the first Asterinas boot on any
  RISC-V development board. Asterinas already documents RISC-V and SiFive
  HiFive Unleashed support.
- **Fail:** The work is not official upstream Megrez support. The local
  development line is substantially ahead of `upstream/main`, and the origin
  repository is not publicly accessible without credentials.

## Forbidden overclaims

- “World first” or “first-ever Asterinas RISC-V board boot.”
- “Asterinas officially supports Milk-V Megrez.”
- “Full USB HID support,” “all keyboards work,” or “complete graphical
  console.”
- “Production-ready,” “stable long-term support,” or “fully working operating
  system.”

## Homepage-safe sentence

> Brought Asterinas up on a physical Milk-V Megrez RISC-V board to an
> interactive `tty0` BusyBox shell, reusing the firmware framebuffer and
> demonstrating basic USB-keyboard input in a controlled, evidence-backed
> canary.
