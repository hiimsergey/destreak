# destreak
A minimal command line program solely fulfilling the function of counting streaks.

```
destreak – the bare minimum attempt at gamification

Usage:
    destreak                        list all registered activities
    destreak <activity>             reset the streak of one activity
    destreak --new <activity>       add a new activity
    destreak --delete <activity>    remove an activity
    destreak --help                 print this message

Data storage:
    either $XDG_DATA_HOME/destreak.bin
    or $HOME/.local/share/destreak.bin

About:
    v0.1.0  GPL-3.0 license
    by Sergey Lavrent
    https://github.com/hiimsergey/destreak
```

## Usage
This little program lets you add activities described by string to a data file to track streaks, i.e. how many days you've been doing or avoiding said activity. For example:

```sh
$ destreak -n fitness
  0 fitness

$ destreak -n "no sweets"
  0 fitness
  0 no sweets
```

By default, the counters are incremented every 24 hours since the registration time. If the streak needs to be broken, you have to do that manually:

```sh
$ destreak fitness
  0 no sweets
```

This is a design choice and is useful for activities you rather want to abstain from.

## Storage
The streaks are stored in binary at `$XDG_DATA_HOME/destreak.bin` or `~/.local/share/destreak.bin` in this format:

```
[for every activity]
title_len_minus_one: 1 byte
title: title_len_minus_one + 1 bytes
timestamp: 8 bytes
```

## Compilation
```sh
git clone https://github.com/hiimsergey/destreak
cd destreak
zig build -Doptimize=ReleaseSmall
```

You can find the binary at `zig-out/bin/destreak`. It obviously doesn't depend on anything, so move it wherever you want.
