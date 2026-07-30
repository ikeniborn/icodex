# Project Profile Manifests

This directory contains approved project manifests read directly from the target
repository. Each manifest names its task requirements and pins the exact byte hash of
the shared profile registry.

Never copy the shared registry or runtime routing state into this directory. Runtime
state is local and disposable; it does not alter approved policy.

`status: approved` requires explicit review before commit. A registry hash change
invalidates manifests and requires review plus a new pin. Unsupported YAML constructs
fail closed.
