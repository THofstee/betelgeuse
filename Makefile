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

rigel:
	ln -s betelgeuse.lua rigel/examples/betelgeuse.lua
	ln -s betelgeuse rigel/examples/betelgeuse
	ln -s examples/* rigel/examples/

clean:
	rm -rf out/*

.PHONY: doc
doc:
	ldoc .

test:
	busted
