#  rootless-ubuntu-arc-runner

A minimal ubuntu based Github runner.

Includes:
- Bun
- Deno
- Go
- Ko
- Node (using node 20 from runner externals)
- Rust (rustc and cargo)
- tko (allowing rootless container building for quarkus, etc)

Expects:
- /tmp and /home/runner to be be mounted as volumes (allowing `readOnlyRootFilesystem: true` on the runner container)
