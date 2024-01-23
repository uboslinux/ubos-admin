# Implementation notes on ratchet upgrades

## The problem

We release UBOS updates on an ongoing basis. Owners of UBOS devices do not necessarily upgrade their devices every time they should. So by the time they do upgrade, they may be several UBOS versions behind.

Some packages (notably Nextcloud) do not tolerate skipped upgrades. So a solution needs to be found to perform the missed updates before updating to the most recent version.

Our upstream distro -- Arch -- provides no functionality for this. Not sure that other Linux distros do. In contrast, one of the reasons Windows upgrades can take so long is that Microsoft indeed performs intermediate updates first.

## Approach

Instead of having repositories like `os` exist only in the then-current version, we create and keep around each version of each repository that we released, with a timestamp, such as `os-20140101T123456Z`.

Each device records the timestamp of the most recent repository that it was successfully upgraded to. When the next upgrade is performed, `ubos-admin update` is performed once for each timestamp that is in the future from the most recent successful update. Each of these upgrades includes backup/restore/running updaters from each deployed application, and may include device reboots.

Note: we will use the Arch terminology of "database file" for the `.db` files, like `os.db`.

## Details

### Repository database names

Currently, `/etc/pacman.conf` contains entries such as:

```
[os]
Server = http://depot-develop.ubosfiles.net/dev/$arch/os
```

where the `Server` is the URL to a directory containing the repository, and the
string in the square brackets refers to the name of the database file (minus extension).

We will add a timestamp to the name of the database file, so `pacman` will read the correct version of the repository, like this:

```
[os-20140101T123456Z]
http://depot-develop.ubosfiles.net/dev/$arch/os
```

Note that multiple versions of the same database file may coexist in the same directory. they may also point to the same, or an overlapping set of package files in the same directory.

### `history.json`

Each repo in the depot will maintain a new file called `history.json` in the same directory as the repository, e.g. `http://depot-develop.ubosfiles.net/dev/$arch/os/history.json`. It contains a series of timestamps which represent the times at which a new version of the repository has been created/published.

This file is consulted by `ubos-admin update` to determine the name of the repository database file to use in `/etc/pacman.conf` for the next upgrade step.

For each entry in `history.json`, a corresponding database file must exist.

If a `history.json` file does not exist for a given repository, the ratchet upgrade algorithm is not applied for this repository and `ubos-admin update` always upgrades to the most recent version. If `history.json` has appeared since the last upgrade, the repository switches from traditional upgrades to ratchet upgrades, starting with the oldest entry in the `history.json` file.

### Purging of package files

A package file may be removed from the depot when none of the database files in the directory still reference that package in that version.

### `last-ubos-update.json`

Each UBOS device maintains a file `last-ubos-update.json` that contains:
* The wall clock time when the device was last successfully upgraded (`upgradeSuccessTs`).
* The timestamp that is the maximum, over all active repositories, of the timestamps of the versions of the repositories that were used in the last successful upgrade (`repositoryPositionTs`).

Note that `repositoryPositionTs` may only be used by a single repository used in the upgrade; other repositories may not have a version at that time stamp and their preceding version was used in the last successful upgrade.

If this file does not exist on a device, the device has not been upgraded successfully with the ratchet upgrade process.

### Upgrade process

When `ubos-admin update` is run in order to upgrade (i.e. not with ``--pacmanConfOnly`` or ``-pkg`` or such), the following steps need to be performed:
.
* For each active repository, obtain the current `history.json`.

* If `history.json` does not exist for a repository, use the database file without a timestamp; the ratchet upgrade algorithm is not in effect for this repository.

* If `last-ubos-update.json` does not exist, we run the ratchet upgrade algorithm for the first time. To do so, use the following calculated value for `repositoryPositionTs` instead: the maximum update timestamp, over the set of active repositories, of the oldest entry in their respective `history.json` files. (This generally should normally cause the oldest version of each repository to be used.)

* Given `repositoryPositionTs`, find the next `repositoryPositionTs`. This is calculated as the minimum timestamp, over all active repositories, of the next entry in each repository's `history.json`. The new value is not written to disk until the upgrade has been successul.

* Given the new `repositoryPositionTs`, calculate

* Regenerate `pacman.conf` with the calculated database names.

* Update the `last-ubos-update.json` file.

* Repeat this process until `repositoryPositionTs` is the maximum timestamp, or greater than the maximum, over all active repositories, of the largest timestamp in any of their `history.json` files. This test should be performed at the beginning of `ubos-admin update`, so we don't undeploy etc if there are no available updates.

Note that the `/etc/pacman.conf` file, after an update, will reference the timestamps of the databases that 1) the most recent upgrade was successfully performed from, or 2) the most recent upgrade was unsuccessful from. This appears to be the appropriate state to either 1) install additional packages from before the next update, or 2) attempt manual fixes to the broken upgrade from.

### Complications

* Not all repositories may be released at the same time (in particular if the device uses non-standard repositories as well). So the upgrade timeline is created as the superset of all upgrades of all repositories. When an upgrade at a particular timestamp occurs, only one or not all repositories may have new packages.

* If a repository is temporarily disabled, and re-enabled later, neither skipping intermediate updates, nor performing them is great; they both create problems. Because skipping intermediate updates is much simpler to implement, we use this bad alternative over the other bad alternative.

## Implementation impact

### Impact on the build/release process

* The `history.json` file needs to be created and updated. This can be done on a per-repository basis; there is no need to have the same timestamp for repositories updated as part of the same run.

* Each database file needs to be published without timestamp (so the existing upgrade mechanism continues to work as "head") and with a timestamp. The most recent timestamped version of the repository and the version without a timestamp will always be the same.

* A package purge mechanism must be implemented that purges package files in versions that are not referenced any more from any of the database files.

### Impact on `ubos-admin update`

* The above upgrade process must be implemented.

* `ubos-admin update` is now performed in a loop that spans `ubos-admin update`, `ubos-admin update-stage2` and potentially several reboots.

### Impact on `ubos-install`

* `ubos-install` needs to determine the `repositoryPositionTs` as the maximum timestamp, across all active repositories, contained in their respective `history.json` files.

* That `repositoryPositionTs` is used to calculate the timestamps for the install-time `/etc/pacman.conf`, and also for the run-time `/etc/pacman.conf`.

* It also needs to be saved to the new installation.
