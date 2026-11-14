#  rootless-ubuntu-arc-runner

A minimal ubuntu based Github runner.

Includes:
- Bun
- Deno
- Go
- Java (OpenJDK 21 JRE)
- Ko
- libclang (for building Rust projects with C FFI bindings, e.g., libavcodec)
- Node (using node 20 from runner externals)
- Python (latest stable, installed via uv into /opt/python; `python`/`python3` on PATH)
- Rust (via rustup with latest stable toolchain)
- tko (allowing rootless container building for quarkus, etc)
- uv / uvx
- Zig (pinned release, verified official tarball in /opt/zig; also usable as a C/C++ cross-compiler via `zig cc`)

Expects:
- /tmp and /home/runner to be be mounted as volumes (allowing `readOnlyRootFilesystem: true` on the runner container)
