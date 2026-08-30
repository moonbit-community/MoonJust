# Architecture

MoonJust is binary-only. The root package owns the entrypoint and all other
implementation is explicitly internal.

```text
main
  -> cli.parse_invocation
  -> application.classify_request
  -> project.load_snapshot
  -> query | planner
  -> runtime.execute_plan
  -> application.render_response
```

`project` owns discovery, source loading, module graphs, semantic compilation,
and working-directory facts. `query` is read-only. `planner` builds an
execution plan and owns dependency order, dry-run, and recipe expansion.
`runtime` executes only an already-built plan. `host` contains capability
contracts and errors; platform adapters are separate packages.

No lower layer imports `application`, `runtime`, or the root package. Host
capabilities are explicit, and the test-only `host_testkit` implementation is
never part of the production Host contract.
