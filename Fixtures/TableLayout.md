# Table column sizing

Short labels must stay readable alongside long descriptions. Tables can use the wider window, while this paragraph keeps its normal reading width.

| Consumer | How it pins the version | Change it for a test |
| --- | --- | --- |
| reader (desktop) | package `preview_api/<v>@example` in `package.lock` | Run `package editable add --user example .` in preview-api, then build reader with `--build=editable` (README, Linux). On the Mac both run inside the reader-sdk container (its package home is `~/.packages-linux`) and the preview-api folder needs an extra `-v` mount, which the wrapper does not add today. Untested on the Mac. |
| device_firmware | submodule `Reader/preview-api` | Point the submodule at your branch, then configure again. |
| mobile | Maven `com.example:preview-api` | Build and publish locally, then update the dependency version for the test. |

## Compact numeric columns

| ID | Count | Description |
| --- | ---: | --- |
| 1 | 24 | A long description should get the space left over after the compact identifiers and numbers have enough room. |
| 2 | 7 | Short description. |

## More columns than a small window can fit

| Consumer | Platform | Dependency | Version | Maintainer | Environment | Description |
| --- | --- | --- | --- | --- | --- | --- |
| desktop | macOS | preview-api | 1.2.3 | Maintainer | Development | Keep each label readable and scroll the table when needed. |

## Long unbroken content

| Kind | Value |
| --- | --- |
| Code | `preview_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz` |
| URL | [https://example.com/abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz](https://example.com/abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz) |
