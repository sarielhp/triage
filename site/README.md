# Project website

This is a static GitHub Pages site, published from `main:/docs` at
<https://sarielhp.github.io/triage/>. It links back to the GitHub repository and
states the Codex/vibe-programming provenance at the top.

`site/index.html` is the editable template. `docs/index.html` is generated and
committed for branch-based Pages publishing; no custom Actions workflow is needed.

```sh
ruby scripts/build_site.rb
```

The builder embeds the verified triangulation SVG and reads benchmark values
from the published CSV files. Site styles and the two mesh controls live in
`docs/assets/site.css` and `docs/assets/site.js`. No analytics, remote fonts,
JavaScript libraries, or build-time package downloads are required.

See [the figure instructions](../figs/README.md) to regenerate the geometry.
Keep the Codex/vibe-programming attribution prominent when revising the template.
