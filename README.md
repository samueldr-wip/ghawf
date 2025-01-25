More Space action
=================

This action will ***aggressively*** make more space in the runner.

This is tuned for actions that do not rely on the provided runtimes.
It may break other actions in unexpected manner.

Supported use-cases:

 - Running Nix and Nix-like builds


* * *

Usage
-----

The following shows an involved example for pairing the LVM span trick with a Nix-based build.

```yaml
name: Build

on:
  pull_request:
  push:
    branches:
      - "latest"

jobs:
  build:
    name: Build requiring more space
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Scrounge-up some more space
        uses: samueldr/more-space-action@latest
        with:
          enable-lvm-span: true
          lvm-span-mountpoint: /nix

      - name: Install Lix
        uses: samueldr/lix-gha-installer-action@v1

      - name: Override nix-daemon build directory
        run: |
          (
          PS4=" $ "
          set -eux -o pipefail
          sudo mkdir -p /nix/tmp
          sudo chmod ug=rwx,o=rwxt /nix/tmp
          sudo mkdir -p /etc/systemd/system/nix-daemon.service.d
          sudo tee /etc/systemd/system/nix-daemon.service.d/override.conf >/dev/null <<EOF
          [Service]
          Environment=TMPDIR=/nix/tmp
          EOF
          sudo systemctl daemon-reload
          sudo systemctl restart nix-daemon
          )

      - run: nix-build
```

> [!NOTE]
> Prefer pinning to a released version, rather than following the latest branch.
>
> This applies to all actions.

The use of Nix or Lix is not a requirement with this action.
It is mainly useful as a less-than-simple example.

Be mindful about the access rights of the mount point, which may not be correct for other use-cases.
By default, it will be owned, by the default, by the `root:root` user/group pair.
If you intend to "just" run commands as the runner user in the mounted span, chowning to the runner user will be necessary.


* * *

Configuring the action
----------------------

There are a couple inputs you can provide to this action.

<!-- ACTION.YML INPUTS START -->

### `additional-apt-patterns`

*Default: ``*

Additional patterns to autopurge with apt.

> [!WARNING]
> This single string will be split according to bash string splitting semantics.


### `enable-remove-default-apt-patterns`

*Default: `true`*

Enable the built-in list of patterns to autopurge.

This effectively disables autopurging if disabled, when no additional patterns are provided.


### `additional-space-hogs`

*Default: ``*

Additional paths to remove.

> [!WARNING]
> This single string will be split according to bash string splitting semantics.


### `enable-remove-default-space-hogs`

*Default: `true`*

Enable the built-in list of space hogs to remove.


### `enable-remove-non-package-usr`

*Default: `true`*

Enable removing some content from `/usr/` that is not managed by the package manager.

(This will not remove `/usr/local` content.)


### `enable-remove-default-home-folder-hogs`

*Default: `true`*

Enable the built-in list of home folder hogs to remove.


### `enable-remove-home-folder-hogs`

*Default: `true`*

Enable removing some large content from the different `/home/` folders.


### `enable-remove-usr-local`

*Default: `true`*

Enable removing `/usr/local` entirely. It is not managed by the package manager.


### `enable-docker-prune-all`

*Default: `true`*

Enable pruning all docker images from system.

Some older images shipped with around 2.5GiB of wasted space from docker images.


### `enable-second-drive-harmonization`

*Default: `true`*

When enabled, if a second drive is attached to the runner (it likely is with GitHub's runners),
the attached drive will be configured to work similarly on all systems:

  - The secondary disk (if needed) will be formatted and mounted to `/mnt`
  - Swap file will be put in the preferred location (see: `swapfile-location`)

This option, in itself, saves no space, but ensures further steps can run under an expected disk layout.


### `enable-swapfile`

*Default: `true`*

When harmonizing the drives, the existing swapfile will be removed.

When this option is enabled, a swapfile is created back in the system.
This option can be used to effectively disable the swapfile entirely.

A swapfile is used by default, just like GitHub's runners do by default.


### `swapfile-location`

*Default: `/swapfile`*

Determine where the swapfile should be created.

GitHub's runners defaults differ:

  - AArch64: /swapfile
  - x86_64: /mnt/swapfile


### `swapfile-size`

*Default: `4GiB`*

Determine the swapfile size.

GitHub's runners defaults differ:

  - AArch64: 3GB
  - x86_64: 4GB

The value is passed to fallocate.


### `enable-lvm-span`

When enabled, files will be created at the listed locations, 

The mountpoint will be left untouched, meaning that chmod or chown is likely to be needed to make use of it in your actions.

> [!NOTE]
> This option makes no sense to enable without `enable-second-drive-harmonization` being enabled.

> [!WARNING]
> If setting-up the lvm span fails, at any point, the action will fail.
>
> Enabling this option means it is necessary for the span to be created.


### `lvm-span-mountpoint`

*Default: `/misc`*

Loction the lvm span will be mounted as


### `lvm-span-mountpoints`

*Default: `/ /mnt`*

Mountpoints under which a file for the LVM span will be created.


### `lvm-span-default-free-space`

*Default: `104857600`*

This numeric option describes the amount of bytes that will be left free by default on drives with an LVM span.

The default value leaves 100MiB free on any given disk.

See also: `lvm-span-free-space`


### `lvm-span-free-space`

*Default: `{
  "/": "1073741824"
}
`*

JSON object listing amount of free space to be left on specific mountpoints.

The default leaves 1GiB free on the rootfs.

See also: `lvm-span-default-free-space`


### `verbose`

When enabled, this action may be overly verbose.


### `dry-run`

When enabled, this action will stub out all system altering commands.


<!-- ACTION.YML INPUTS END -->

* * *

FAQ
---

### Why this action instead of others?

I'm not 100% sure. I know of one other action. Its future is uncertain.

What I needed is an action *I* could rely on, for a relatively narrow use-case.

So it is possible it's not suited for your particular use-case.
If it isn't feel free to ask if a contribution that helps your use-case is desirable.


### Is this safe?

Likely yes.

It's been made in a way where it will ignore failures to apply changes to the system.

So at worst, the space savings will not be as good as expected.
