# Third-party notices

## LEOBOG AMG65 protocol

KeyMapper's LEOBOG AMG65 support (`Sources/KeyMapperCore/ScreenKeyboards/`: protocol, LED renderer, scene choice, key layout, LCD and LED-matrix uploads) is ported from
[AMG65 Studio](https://github.com/kocakli/amg65-studio), by the same author as KeyMapper. AMG65 Studio's protocol
code builds on [aumbro/leobog_amg65_rgb](https://github.com/aumbro/leobog_amg65_rgb), used under the MIT License:

```
MIT License

Copyright (c) 2026 Aum (aumbro)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## AI usage engine (CodexBar)

`Sources/KeyMapperUsage/` is ported from AMG65 Studio's UsageEngine, which adapts provider authentication formats,
endpoint contracts and quota parsing from [CodexBar](https://github.com/steipete/CodexBar) (pinned at
`53f9e1e24d28b0d7f451449b4a25d0e076ea5bc9`). KeyMapper does not need the CodexBar app, CLI, preferences or caches.
Adaptations: three providers, bounded no-redirect HTTPS to three fixed hosts, non-interactive Keychain reads in a
separate helper process, no credential refresh or persistence, no browser-cookie import, no account identifiers in
displayed data.

```
MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## QMK, VIA and Vial

The lighting commands and effect names in `Sources/KeyMapperCore/Lighting/` follow the public protocol definitions of
[QMK](https://github.com/qmk/qmk_firmware) (`quantum/via.h`) and [Vial](https://github.com/vial-kb/vial-qmk)
(`quantum/vialrgb.h`, vial-gui's effect table). No source code from those projects is included.
