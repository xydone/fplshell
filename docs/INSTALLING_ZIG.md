# Installing Zig

There are two ways to install Zig.

1. [Use a Zig version manager](#installing-zig-with-a-version-manager) (recommended).
2. [Install Zig manually](https://ziglang.org/download/#release-0.14.1).

## Installing Zig with a version manager.

At the time of writing this, there are many version managers from which you can choose, but this guide will focus on using [`zvm`](https://github.com/tristanisham/zvm).

Note, all of the information below is from [`zvm`'s README](https://github.com/tristanisham/zvm/blob/master/README.md).

### Linux, MacOS

On Linux and MacOS, run the following command to install `zvm`

    curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash

---

### Windows

On Windows, run the following command inside `cmd.exe` to install `zvm`

    powershell -c "irm https://raw.githubusercontent.com/tristanisham/zvm/master/install.ps1 | iex"

After that, you will need to update your `$PATH`. You can use [this](https://www.computerhope.com/issues/ch000549.htm) guide on how to locate the `$PATH` menu.

When you have the menu open,

Add this to your path:

    ZVM_INSTALL: %USERPROFILE%\.zvm\self

Append this to your path:

    PATH: %USERPROFILE%\.zvm\bin
    PATH: %ZVM_INSTALL%

---

Once you've installed `zvm`, restart your terminal (if required) and run

    zvm i 0.14.1

When that is completed, use `zig version` to see if the installation was successful. You should see `0.14.1`.
