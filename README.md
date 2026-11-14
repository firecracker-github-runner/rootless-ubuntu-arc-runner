#  rootless-ubuntu-arc-runner

A minimal ubuntu based Github runner.

Includes:
- Bun
- Deno
- Go
- Java (OpenJDK 21 JRE)
- Ko
- libclang (for building Rust projects with C FFI bindings, e.g., libavcodec)
- Node 22 with npm and corepack (the default `node` on GitHub-hosted Ubuntu runners; from the official `node` image, installed in `/home/runner/.node` so `npm install -g` and `corepack enable` work)
- Python (latest stable, installed via uv into /opt/python; `python`/`python3` on PATH)
- Rust (via rustup with latest stable toolchain)
- tko (allowing rootless container building for quarkus, etc)
- uv / uvx

Expects:
- /tmp and /home/runner to be be mounted as volumes (allowing `readOnlyRootFilesystem: true` on the runner container)
