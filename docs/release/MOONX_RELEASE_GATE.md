# Manual MoonX release verification

After publishing a version with `moon publish --frozen`, select the **published version's tag or branch** in Actions → **MoonX release verification** → **Run workflow**. This workflow does not publish, run on a pull request, or substitute a local Wasm build for the registry asset.

All three hosts (Linux, macOS and Windows) run the same smoke suite against `moonx --target wasm <name>@<version>`. The driver obtains both fields from the selected revision's `moon.mod`, checks the returned product version and compares behavior with official `just 1.57.0`. A missing registry asset receives bounded retries and fails verification if it remains unavailable.

The suite checks version/help, recipe success and failure, stdout/stderr, argument forwarding, format checks, dependencies, working directories, parallel execution, dotenv and cache behavior. Each job uploads its JSON report. Only three successful jobs verify the release; there is no “not applicable” result. The full upstream corpus belongs to the automatic differential workflow.

To repeat on one host, from the matching checkout:

```sh
moon run --target native ./tests/moonx -- --report _build/moonx-report.json
```
