#  rootless-ubuntu-arc-runner

A minimal ubuntu based Github runner.

Includes:
- Bun
- Deno
- ffmpeg (with libavcodec)
- Go
- Java (OpenJDK 21 JRE)
- Ko
- Node (using node 20 from runner externals)
- Rust (via rustup with latest stable toolchain)
- tko (allowing rootless container building for quarkus, etc)

Expects:
- /tmp and /home/runner to be be mounted as volumes (allowing `readOnlyRootFilesystem: true` on the runner container)
