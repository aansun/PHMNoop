# Third-party notices

PHMN is a fork of NOOP and keeps NOOP's license, [PolyForm Noncommercial 1.0.0](LICENSE). It also uses the projects below, under
their own licenses. The same notices are in the app under **Me › About and help › Open-source notices**.

## MuscleMap: body map

Swift package `https://github.com/melihcolpan/MuscleMap`, version 1.6.4, by Melih Colpan, used under the **MIT License**. It draws
the body map of the Gym screens (the muscle map and the exercise detail). iOS target only.

```
MIT License

Copyright (c) 2026 Melih Colpan

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

## free-exercise-db: exercise library

`https://github.com/yuhonas/free-exercise-db` by yuhonas, released into the public domain under **The Unlicense**. The app bundles
its exercise names, muscles, equipment and instructions, and two photos per exercise (the start and the end of the movement,
shrunk to 520 px wide). `Tools/build-exercise-library.py` builds the bundle in `StrandiOS/Resources/ExerciseLibrary/`.

The data set says it is derived from the public-domain `wrkout/exercises.json`. The original photographer is not named upstream and
this project could not verify the chain of rights beyond the dedication at the source.

```
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means. For more information, see
https://unlicense.org
```

## openGym: inspiration only

`https://github.com/DuarteSantos8/openGym` by Duarte Santos is licensed under the **GNU AGPL-3.0**. The idea of a body map showing which
muscles are trained and which are still tired came from it. **No openGym code, data, photos or animations are in PHMN.** The muscle
readings (`NunaMuscleReadiness`) and the library are written from scratch or come from the projects above, so PHMN is not a derivative
work of openGym and keeps NOOP's license. openGym's own exercise photos and animations are of unsettled ownership upstream and are
not used.

## Fonts and MarkdownUI

- D-DIN-PRO and Montserrat: **SIL Open Font License 1.1**; the license texts ship in `StrandiOS/Resources/Fonts/`.
- MarkdownUI (`gonzalezreal/swift-markdown-ui`): **MIT License**, Guillermo Gonzalez.
