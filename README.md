#  rootless-ubuntu-arc-runner

A minimal ubuntu based Github runner.

Includes:
- Bun
- Deno
- Go
- Java (OpenJDK 21 JRE)
- Ko
- libclang (for building Rust projects with C FFI bindings, e.g., libavcodec)
- Node 24 (from the runner's `externals/node24`, the same Node the runner uses for JavaScript actions)
- Python (latest stable, installed via uv into /opt/python; `python`/`python3` on PATH)
- Rust (via rustup with latest stable toolchain)
- tko (allowing rootless container building for quarkus, etc)
- uv / uvx

Expects:
- /tmp and /home/runner to be be mounted as volumes (allowing `readOnlyRootFilesystem: true` on the runner container)
