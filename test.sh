set -u

bin=zig-out/bin/destreak
data=~/.local/share/destreak.bin
rm $data
$bin -n sweets
$bin -n sours
$bin -d sweets
$bin -d sweets
[ $? -eq 1 ] || exit 1
