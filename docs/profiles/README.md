# Profile Policy

Tracked policy is not runtime state. Runtime state is local and disposable; it does not
alter approved routing policy.

`status: approved` requires explicit review before commit. Registry hash changes
invalidate topic manifests, so a changed registry requires review and a new manifest
pin.

Capability, context, and throughput use `gte` comparisons. Latency and cost use `lte`
comparisons.

Live remaining context is not inferred from catalog context capacity. A task requiring
that confirmation must use a separately documented supported source.

Unsupported YAML constructs fail closed.
