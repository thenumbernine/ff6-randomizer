### Final Fantasy VI Library

[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

This hacks out (tentatively) all the resources of the game.
It outputs text and data structures to stdout.
Images are written to png files.
Audio is written to BRR and WAV files.

Usage: `luajit run.lua <romfile> [<randomized-outfile>]`

There is a half-finished randomizer at the end of `run.lua`.  Pass a second argument to write out a randomized ROM.

Requirements:
- [luajit](https://github.com/LuaJIT/LuaJIT)
- [template](https://github.com/thenumbernine/lua-template)
- [ext](https://github.com/thenumbernine/lua-ext)
- [lua-ffi-bindings](https://github.com/thenumbernine/lua-ffi-bindings)
- [struct](https://github.com/thenumbernine/struct-lua)
- [vec-ffi](https://github.com/thenumbernine/vec-ffi-lua)
- [audio](https://github.com/thenumbernine/lua-audio)
- [image](https://github.com/thenumbernine/lua-image)

Resources:
- http://www.rpglegion.com/ff6/hack/ff3info.txt
- https://github.com/subtractionsoup/beyondchaos
- https://github.com/everything8215/ff6
- https://github.com/everything8215/ff6tool
- just asking everything8215
