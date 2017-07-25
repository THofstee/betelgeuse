package = 'betelgeuse'
version = '0.1.0-1'

source = {
   url = 'git@github.com:THofstee/betelgeuse.git'
}

description = {
   summary = 'summary',
   detailed = [[
      lol idk
   ]],
   homepage = '...',
   license = '...',
}

dependencies = {
   'lua >= 5.1, < 5.4',
}

build = {
   type = 'none',
   install = {
      lua = {
	     ['betelgeuse.lang'] = 'betelgeuse/lang.lua',
	     ['betelgeuse.passes'] = 'betelgeuse/passes.lua',
	     ['betelgeuse.passes.translate'] = 'betelgeuse/passes/translate.lua',
      }
   }
}