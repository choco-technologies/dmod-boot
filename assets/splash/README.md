# Splash logos

Logos the display driver ([dmlcdtft](https://github.com/choco-technologies/dmlcdtft))
shows in the middle of the screen as soon as the display is up, before
anything else draws on it. A board picks one by name in its `board.cmake`:

```cmake
set(DMBOOT_SPLASH_LOGO "dmodos_logo_128" CACHE STRING "Splash logo the display driver shows at start")
```

The build unpacks `<name>.dmvi` into a `.dmvir` - the same image with raw,
uncompressed pixels, so the driver only copies and blends them - and puts it
into the embedded views filesystem at `DMBOOT_SPLASH_LOGO_PATH`
(`/eviews/splash_logo.dmvir`), whose path dmod-boot passes to the driver in
the `SPLASH_LOGO` environment variable. The background of the splash screen
is the display's `clear_color` (dmlcdtft's `lcd.ini`): for the dmodOS logo
`0xFF041431`, the dark navy of the dmodOS splash background.

## Assets

| Asset | Size | Unpacked (`.dmvir`) |
|-------|------|---------------------|
| `dmodos_logo_64` | 75x64 | 14 KiB |
| `dmodos_logo_96` | 112x96 | 32 KiB |
| `dmodos_logo_128` | 150x128 | 57 KiB |
| `dmodos_logo_160` | 187x160 | 88 KiB |
| `dmodos_logo_200` | 234x200 | 138 KiB |

All are `RGB565A8` `.dmvi` files (dmview's image format) made from
`dmodos_logo.png` - the dmodOS mark with its wordmark, on a transparent
background. The unpacked size is what the logo takes in flash.

## Adding a size or a logo

Convert the PNG with [todmvi](https://github.com/choco-technologies/todmvi)
(it needs the `dmimg_png` decoder where dmod finds modules - `dmf-get todmvi dmimg_png`):

```bash
dmod_loader $DMOD_DMF_DIR/todmvi.dmf --args dmodos_logo.png -f rgb565a8 -s x128 -o dmodos_logo_128.dmvi
```

`-s x<height>` scales it to that height, keeping the aspect. The driver draws
`RGB565`, `RGB565A8` and `ARGB8888` images.
