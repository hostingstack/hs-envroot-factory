#
# Rebuild template for envroot-factory

0 4	* * *	root	[ -x /usr/lib/hs/envroot-factory/bin/envroot-factory-rebuild-template ] && /usr/lib/hs/envroot-factory/bin/envroot-factory-rebuild-template >/dev/null
