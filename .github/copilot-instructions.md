# Copilot Instructions for rootless-ubuntu-arc-runner

## Repository Overview

This repository contains a minimal Ubuntu-based GitHub Actions runner Docker image designed for rootless container execution. The runner is optimized for building and deploying Go, Node.js, Rust, and other polyglot applications in a secure, rootless environment.

**Key Technologies:**
- Base: Ubuntu Noble (24.04 LTS)
- GitHub Actions runner from `ghcr.io/actions/actions-runner:latest`
- Languages: Go, Node.js 20, Rust, Bun, Deno
- Build tools: Ko (for Go container builds), tko (for rootless container building)
- Container: Docker (rootless compatible)

## Architecture

**Multi-stage Dockerfile Architecture:**
The Dockerfile uses a multi-stage build pattern:
1. Binary extraction stages (bun, deno, golang, tko) - extract binaries from official images
2. Builder stage - downloads and builds additional binaries (ko)
3. Final Ubuntu-based stage - assembles the runner with all tools

**Key Design Decisions:**
- Uses `/home/runner_base` at build time to stage content that will be copied to `/home/runner` at runtime
- Runtime expects `/tmp` and `/home/runner` to be mounted as volumes, allowing `readOnlyRootFilesystem: true`
- Rust toolchain installed in `${BASE_DIR}/.cargo` and `${BASE_DIR}/.rustup` to persist across volume mounts
- Runner user has UID 1001, GID 0 for OpenShift compatibility

## Project Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yaml          # CI workflow: builds Docker image on PRs and main branch
│       └── publish.yaml     # Publishes image to ghcr.io on main branch
├── Dockerfile               # Multi-stage Docker build definition
├── build-bin.sh            # Script to download ko binary from GitHub releases
├── entrypoint.sh           # Container entrypoint that copies runner_base to runner
├── renovate.json           # Renovate configuration for dependency updates
└── README.md               # Project documentation
```

## Build Instructions

**Building the Docker Image:**
```bash
docker build -t rootless-ubuntu-arc-runner .
```

The build process:
1. Extracts binaries from official images (bun, deno, go, tko)
2. Runs `build-bin.sh` to download ko binary
3. Assembles final Ubuntu image with all tools and dependencies
4. Installs Rust toolchain as runner user
5. Sets up GitHub Actions runner from base image

**CI Build Process:**
- CI runs automatically on pull requests and main branch pushes
- Uses `docker/build-push-action` to build the image
- No tests are run; validation is successful build completion
- On main branch, the publish workflow pushes to ghcr.io

**Build Time:**
The Docker build typically takes 3-5 minutes depending on network speed and layer caching.

## Testing and Validation

**No formal test suite exists.** Validation is through:
1. Successful Docker build completion
2. Manual testing of the runner in a Kubernetes/container environment
3. CI workflow must complete successfully for PRs to merge

**To manually test changes:**
```bash
# Build the image
docker build -t rootless-ubuntu-arc-runner:test .

# Run the container (requires GitHub runner token)
docker run --rm \
  -v /tmp:/tmp \
  -v runner-home:/home/runner \
  -e RUNNER_TOKEN=<your-token> \
  rootless-ubuntu-arc-runner:test
```

## CI/CD Workflows

**.github/workflows/ci.yaml:**
- Triggers: PRs and main branch pushes
- Action: Builds Docker image without pushing
- Purpose: Validates Dockerfile and build process

**.github/workflows/publish.yaml:**
- Triggers: Main branch pushes only
- Action: Builds and pushes to ghcr.io
- Registry: ghcr.io/firecracker-github-runner/rootless-ubuntu-arc-runner

## Dependencies

**Pinned Dependencies:**
All image references use SHA256 digests for security and reproducibility:
- Bun, Deno, Golang, TKO: Extracted from official images
- Ko: Downloaded from GitHub releases (latest tag)
- Actions runner: From `ghcr.io/actions/actions-runner:latest`

**Renovate:**
Automated dependency updates configured in `renovate.json`:
- Extends best practices config
- Auto-merges digest updates
- Auto-approves updates

## Common Tasks

**Adding a new binary/tool:**
1. If available as a Docker image, add a new stage in Dockerfile and COPY from it
2. If downloadable, update `build-bin.sh` with fetch logic
3. Ensure binary is copied to `${BIN_DIR}` in final stage
4. Test the build completes successfully

**Updating base images:**
Renovate handles this automatically. Manual updates:
```bash
# Get latest digest for an image
docker pull <image>
docker inspect <image> | grep -i digest
```

**Modifying runner configuration:**
- Entrypoint logic: Edit `entrypoint.sh`
- Environment variables: Edit Dockerfile ENV declarations
- Runner dependencies: Edit Dockerfile apt-get install section

## Important Notes for Code Changes

1. **Always test Docker builds** after making changes - run `docker build .` locally
2. **Preserve digest pinning** - use SHA256 digests for all image references
3. **PATH considerations** - PATH includes Go, Node, and Cargo bin directories
4. **Volume mounts** - Remember that `/home/runner` is mounted at runtime, so build-time content must go in `/home/runner_base`
5. **Rootless compatibility** - Avoid requiring root privileges for runtime operations
6. **No removal of existing tools** - This image is used in production; don't remove tools without explicit requirement
7. **CI must pass** - All PRs must have successful CI builds before merging

## Troubleshooting

**Build failures:**
- Check network connectivity for downloads in `build-bin.sh`
- Verify all image digests are valid and accessible
- Review apt package availability in Ubuntu Noble

**Runtime issues:**
- Ensure volumes are mounted correctly (`/tmp` and `/home/runner`)
- Check that runner token is provided
- Verify user has access to Docker socket if building containers

**Rust toolchain issues:**
- Rust is installed in `${BASE_DIR}/.cargo` and `${BASE_DIR}/.rustup`
- PATH includes `${BASE_DIR}/.cargo/bin`
- Installation uses default stable toolchain
