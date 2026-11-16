# Publishing this plugin

This file tracks the public-release route; it is not part of the installed UI.

## 1. Replace the placeholders

Replace every `KevinMKRL` in:

- `package.json` (`repository`, `bugs`, `homepage`)
- `README.md` (install command)
- `market/awesome-dsh-plugin-entry.yml` (`url`, `name`, `icon`)

The package name `dsh-windows-screenshot` was free on the public npm registry
when this file was written. The GitHub repository should use the same name.

## 2. Publish the repository

Create a public GitHub repository named `dsh-windows-screenshot`, push this
directory, and add the **`dsh-plugin`** topic. The README must keep a copyable
install command: `dsh plugin --profile web add github:OWNER/dsh-windows-screenshot`.

## 3. Marketplaces

- **DSH Discover / awesome-dsh-plugin:** open a PR that adds
  `data/plugins/<owner>__<repo>.yml` to
  <https://github.com/awesome-dsh-plugin/awesome-dsh-plugin>, using
  `market/awesome-dsh-plugin-entry.yml`. The repo must be public for at least
  one day, have the `dsh-plugin` topic, and be actively maintained. This registry
  is curated and may treat an existing screenshot plugin as covering this one.
- **dsh.so:** paste the repository URL at <https://www.dsh.so/zh/submit/>. The
  checker fetches the public repo, validates the manifest, scans the source, and
  queues a submission issue for review. A recognizable SPDX license and a README
  with install instructions are required.
- **dsh-plugin.org / DSH Plugin Hub:** public GitHub repo + `dsh-plugin` topic;
  the hub's automated scan handles the rest. Its submit page is
  <https://dsh-plugin.org/submit>.
- **DSH Web Discover tab:** there is no central upload endpoint. The built-in
  Discover tab reads indexes the user configures. Listing in awesome-dsh-plugin
  or dsh.so makes the plugin available through those indexes; a private index is
  also possible but is not a public marketplace listing.

## 4. Optional npm release

```sh
npm publish --access public
```

The package is unscoped, so it needs an npm account whose name is not already
taken. After publishing, the install command in the README becomes
`dsh plugin --profile web add dsh-windows-screenshot`.

## 5. Verify

After listing:

- Add the index source in DSH **Plugins → Discover** (or the marketplace's own
  UI) and search for the package name.
- Install from the listed spec on a clean profile.
- Confirm the camera button, all three modes, delay, cancel, and automatic draft
  import still work.
