---
name: docker-container-build
description: Build or review production container images and Dockerfiles with emphasis on reproducible builds, dependency hygiene, Docker layer/cache efficiency, image size reduction, non-root runtime, secrets handling, and security hardening. Use when Codex writes, edits, audits, or explains Dockerfile, Containerfile, docker-compose.yml, compose.yaml, .dockerignore, uv-based Python container builds, Node/Python dependency installation in images, multi-stage builds, or container build performance/security tradeoffs.
---

# Docker Container Build

## Workflow

Use this skill to design or review container builds. Start by identifying runtime language, package manager, build artifacts, native build dependencies, runtime-only dependencies, expected entrypoint, exposed ports, and whether the image is for local development or production.

Prefer the smallest design that is reproducible and debuggable:

1. Pin base image and dependency inputs.
2. Separate dependency install from source copy to preserve cache.
3. Use multi-stage builds when build tools, compilers, package managers, test assets, or dev dependencies are not needed at runtime.
4. Keep final image runtime-only, non-root, and free of secrets.
5. Verify build, run, health, image size, layer contents, and security posture with actual commands when possible.

## Image Base

- Prefer official, maintained base images from trusted registries.
- Avoid `latest`; pin concrete tags. Use digests when supply-chain reproducibility matters.
- Verify image signatures or provenance when the project uses signed images, registry attestations, or a hardened supply-chain policy.
- Prefer `slim`, `alpine`, `distroless`, or `scratch` only when compatible with the app and its native dependencies.
- Use matching build/runtime ABI families. For Python, avoid mixing builder and runtime variants that put the interpreter at different paths or use incompatible libc.
- Treat minimal images as a tradeoff: smaller attack surface, but less debugging tooling and possible native package friction.

## Dependencies

- Copy lockfiles/manifests before source code:
  - Node: `package.json`, lockfile, then `npm ci --omit=dev` or equivalent production install.
  - Python pip: requirements or lockfile, then `pip install --no-cache-dir`.
  - Python uv: `pyproject.toml` and `uv.lock`, then `uv sync --frozen --no-dev`.
- Install only production dependencies in final images. Keep test, lint, compiler, and build packages in builder stages.
- Pin package versions where operational reproducibility matters.
- Clean package-manager indexes and temp files in the same `RUN` layer that creates them.
- Never bake credentials into `ENV`, `ARG`, lockfiles, package manager config, or copied dotfiles.
- Use BuildKit secrets for private registries or tokens:

```dockerfile
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci --omit=dev
```

## Layers and Cache

- Order layers from least-changing to most-changing: base setup, system packages, dependency manifests, dependency install, source copy, build, runtime config.
- Combine related install/cleanup commands in one `RUN` so deleted files do not remain in earlier layers.
- Do not combine unrelated high-churn commands merely to reduce layer count; cache quality matters more than a tiny layer count.
- Use `.dockerignore` to exclude `.git`, local caches, test outputs, node_modules, virtualenvs, secrets, logs, and other build-context noise.
- Prefer BuildKit cache mounts for package managers:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev
```

- Use `COPY` for local files. Use `ADD` only when automatic archive extraction is deliberately wanted; avoid remote `ADD`.
- Use `COPY --from=builder` to move only runtime artifacts into final image.

## Python with uv

For production Python images with `uv`, prefer a builder stage plus slim runtime:

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=0
WORKDIR /app

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.12-slim-bookworm
RUN groupadd -r app && useradd -r -g app -d /app -s /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH"
USER app
CMD ["python", "-m", "your_app"]
```

Adjust this pattern before use: choose the real command, verify writable paths for the `app` user, and ensure the builder/runtime Python paths are compatible. Use standalone `uv`-managed Python only when exact Python version control matters more than minimal runtime size.

## Runtime Hardening

- Create a dedicated non-root user and switch with `USER` after files and permissions are set.
- Use `COPY --chown` or explicit `chown` for writable app paths.
- Add a meaningful `HEALTHCHECK` for long-running services when the orchestrator does not supply one.
- Use JSON-form `ENTRYPOINT`/`CMD` so signals reach the process correctly. If a shell wrapper is required, end it with `exec`.
- Log to stdout/stderr. Do not require writable log files inside the image unless a volume or writable path is part of the runtime contract.
- Do not hard-code secrets or environment-specific values. Use runtime environment variables, secret stores, or orchestrator secrets.
- Consider read-only root filesystem, dropped capabilities, seccomp/AppArmor, and non-privileged mode in Compose or orchestration config.
- Label images with source/version metadata when useful for operations.

## Compose Guidance

- Keep Compose development conveniences separate from production image design.
- Use named volumes for persistent state and explicit networks for service isolation.
- Put environment-specific values in `.env` or external config, not in the image.
- Define health checks, restart policies, resource limits, and service dependencies where they reflect real runtime expectations.
- Use immutable service image references and explicit pull policy when Compose is part of deployment.
- Configure replicas/scaling only when the service is stateless or has a clear coordination model.
- Use Compose watch/sync only for local development loops.

## Review Checklist

Before accepting a Dockerfile or Compose change, check:

- Base image is trusted and pinned.
- Build context is controlled by `.dockerignore`.
- Dependency lockfiles are copied before application source.
- Final image excludes build tools, dev dependencies, caches, tests, and secrets.
- Layer order preserves cache for dependency installs.
- Package indexes/temp files are cleaned in the same layer where created.
- Runtime runs as non-root with correct ownership and writable paths.
- Entrypoint handles signals; service has health behavior if needed.
- Logs go to stdout/stderr, not hidden files inside the image.
- Ports, env, volumes, Compose networks, pull policies, and scaling settings match the app contract.
- Image signing, SBOM, and vulnerability scanning expectations are satisfied when the project requires them.
- Verification commands were run or explicitly skipped with reason.

## Verification Commands

Prefer real checks over visual inspection:

```bash
docker build --progress=plain -t app:test .
docker image ls app:test
docker history --no-trunc app:test
docker run --rm app:test --help
docker run --rm --entrypoint sh app:test -c 'id && find / -maxdepth 2 -name "*.pem" -o -name ".env" 2>/dev/null | head'
```

When available, add project-specific checks:

```bash
docker run --rm app:test python -m pytest
trivy image app:test
docker scout cves app:test
hadolint Dockerfile
dive app:test
cosign verify <published-image-ref>
```
