### Workflow

#### Initial setup

Clone our git repository.
`git clone https://github.com/analogdevicesinc/linux.git`

#### Writing a driver

Checkout a new branch.

If developing for a Raspberry Pi, use `staging-rpi/name` for the branch name,
where `name` is the name of your chip, or the name of your chip and the feature
you are currently adding, or the name of your chip and the problem you are
currently solving.

If developing for a Xilinx or an Intel board, use `staging/chip-name`.

This special branch naming scheme is needed for the CI to compile and test your
code automatically on each push.

If you are developing for a Raspberry Pi board, you will still need to use the
`staging/` prefix when making a pull request, so you will need to
`git cherry-pick` all the commits you made onto a `staging/name` branch.

Besides the driver, you will most likely also need a device-tree file.
Also, you need to add the driver to one of our Kconfig.adi files, depending on
which subsystem you are working on.
`find -name "Kconfig.adi"`

Do these actions in two separate commits, which will not be upstreamed.

While developing your driver, make sure to follow the observations inside
`upstream-suggestions.md`, since these are common issues will be pointed out in
our internal review, or in the upstream review.

Make sure to run `./scripts/checkpatch.pl` on all your patches, and also
validate all your schemas using `make dt_binding_check`.

This will be done automatically by the CI anyway, but it is nice to handle it
before the review happens.

The `send-patches.sh` script contains more in-depth steps necessary for running
these checks.

Once your driver/feature/fix is in a working state, `git push` your branch to
Github.

Wait for reviews. Correct anything pointed out, and then `git push -f` for more
review, and leave a comment describing the changes since your last revision, eg:
```
V1 -> V2:
 * x changed to y
 * z changed to w
```
Once everything is handled and no one has any objections left, you can start
upstreaming these patches.

#### Upstreaming

Upstreaming can be a very tedious process.

Add the upstream IIO tree as a remote.
`git remote add iio https://git.kernel.org/pub/scm/linux/kernel/git/jic23/iio.git`

If working on other subsystems, the trees for these can be found on
`git.kernel.org` or in the `MAINTAINERS` file.

For IIO, checkout the `testing` branch.
`git checkout iio/testing`

Cherry pick all your commits from your original working branch.
There's a `pick-patches.sh` script that can help you do that.

Make sure your driver compiles. Upstream linux can have changes that might not
be present in our tree and that will break the compilation of your driver.

To maintain compatibility with our tree, you can keep the original driver commit
upstream-compatible, and add commits prefixed with `[COMPAT]` (these will be
skipped by the `pick-patches.sh` script) to fix the compatiblity for our tree.

For ARM64, you can use the default defconfig as a base.
`make defconfig`

Then, `make menuconfig` and enable your driver (you can use `/` to search for 
the `Kconfig` entry of your driver).
You might also need to enable its dependencies (`depends on X` in `Kconfig`)
before seeing the driver entry itself.

Afterwards, you need to generate patches for your commits and send these patches
upstream using `git send-email`.

The `send-patches.sh` script describes the steps needed to do so more in-depth.

`git send-email` needs some special configuration that won't be covered by this
document, since some people use their work email for it, and some use their
personal email.

Once you receive review from upstream maintainers, make the necessary changes,
and repeat these steps.

Development should continue to be done in the branch based on our tree, so that
you can still test your driver on real hardware.

When generating updated patches, use the `-v`  and `--cover-letter` paramters of
`git send-email` (also handled by that script). In the generated cover letter,
mention the changes between revisions just like you did in the pull-request
comments.

When everything is good to go upstream, your patches will be picked to the
respective tree and will land in the next Linux version. Congrats!

### Merging back into our tree

Once you can see the upstream commits in the respective tree, you can pick them
back to our tree, and squash the `[COMPAT]` patches back into the driver commit
using `git rebase -i`.

When cherry-picking the upstream commits, make sure to use the `-x` parameter
for `git cherry-pick`, so that a line mentioning the upstream commit id is
added to the commit message.
