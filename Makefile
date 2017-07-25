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
	ln -rs betelgeuse.lua rigel/examples/betelgeuse.lua
	ln -rs betelgeuse rigel/examples/betelgeuse
	ln -rs examples/* rigel/examples/

.PHONY: rigel-clean
rigel-clean:
	unlink rigel/examples/betelgeuse.lua
	unlink rigel/examples/betelgeuse
	# unlink rigel/examples/*.lua

.PHONY:derp
derp:
	# echo 
	# $(foreach dir,'examples',$(wildcard $(dir).*))

clean:
	rm -rf out/*

.PHONY: doc
doc:
	ldoc .

test:
	busted
