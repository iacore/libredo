Reactive signal/Dependency tracking library in Zig. Data management not included. Possible application: writing UI or build system logic.

Dependency graph data structure inspired by [redo](https://github.com/apenwarr/redo). Dependency tracker algorithom inspired by [trkl](https://github.com/jbreckmckye/trkl). Benchmark code adapted from [maverick-js/signals](https://github.com/maverick-js/signals/pull/19/files#diff-ed2047e0fe1c26b6afee97d3b120cc35ee4bc0203bc06be33687736a16ac4a8e).

## Documentation

Read [src/main.zig](src/main.zig).

## Use as library

This is a Zig-only library. The module name is called `signals`.

If you don't know how to use a Zig library, use the search engine.

## Todo

- add test suite more more tests
- add solid.js-like interface

## optimization ideas

The current `BijectMap` is fast enough already.

- cache lookup, so `BijectMap.add` can be used later faster
- coz: tested. not useful.
- ReleaseFast: same speed as ReleaseSafe.
