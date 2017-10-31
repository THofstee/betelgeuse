LUA_DIR=/usr/local
LUA_LIBDIR=$(LUA_DIR)/lib/lua/5.1
LUA_SHAREDIR=$(LUA_DIR)/share/lua/5.1

install:
	mkdir -p $(LUA_SHAREDIR)/betelgeuse
	# cp betelgeuse.lua $(LUA_SHAREDIR)
	cp -r betelgeuse/* $(LUA_SHAREDIR)/betelgeuse

uninstall:
	# rm -f $(LUA_SHAREDIR)/betelgeuse.lua
	rm -rf $(LUA_SHAREDIR)/betelgeuse

.PHONY: rigel
rigel:
	ln -frs rigel/examples/makefile examples/Makefile
	ln -frs rigel/examples/*.raw examples
	ln -frs rigel/misc misc
	ln -frs rigel/platform platform
	mkdir -p examples/out

.PHONY: rigel-clean
rigel-clean:
	rm -f examples/Makefile
	rm -f examples/*.raw
	rm -rf misc
	rm -rf platform

clean:
	rm -rf out/*

.PHONY: results
results: rigel
	mkdir -p examples/dbg
	mkdir -p results/graphs
	luajit results/run-tests.lua

.PHONY: doc
doc:
	ldoc .

test:
	busted
