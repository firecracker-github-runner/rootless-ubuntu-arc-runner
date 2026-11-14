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
- Zig (latest stable official release in /opt/zig, `zig` on PATH; downloaded from the [community mirrors](https://ziglang.org/download/community-mirrors/) and minisign-verified. Pin a release with the `ZIG_VERSION` build arg)

Expects:
- /tmp and /home/runner to be be mounted as volumes (allowing `readOnlyRootFilesystem: true` on the runner container)
