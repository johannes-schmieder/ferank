# Stata SPI provenance

`stplugin.c` and `stplugin.h` are version 3.0 of StataCorp's public plugin
interface files, copied from the owner's locally qualified `fereg` plugin
source on 2026-08-28. StataCorp publishes the interface sources at
[`stplugin.c`](https://www.stata.com/plugins/stplugin.c) and
[`stplugin.h`](https://www.stata.com/plugins/stplugin.h); their copyright
headers are retained. The bundled files have these SHA-256 values:

```text
7f954e5985c53bb80533d0cbd5df794c0aaa94de2a69013e3b8c610d9011c69a  stplugin.c
2ff392f78fdef0a41602994f6cf540ead3e1bfe4f1ef8336a5f2055fd2f2b3f1  stplugin.h
```

`stata_bridge.c` and `stata_bridge.h` are repository-authored GPL-3.0-only
wrappers. They retain the Stata function-table pointer in C, bind calls to the
Stata thread, expose only the small set of read/store/display operations needed
by `ferank`, and call Rust through a panic-protected dispatcher. No Stata
license material is included.
