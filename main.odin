package main

import "core:fmt"
import "core:log"
import "core:net"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/db"
import "oryn:app/config"
import "oryn:app/global"
import "oryn:app/view"
import "oryn:app/middleware"
import app_router "oryn:app/router"

// run test:
// > odin run . -collection:oryn=oryn -debug
main :: proc() {
	context.logger = log.create_console_logger(.Info)

	app := gh.new(gh.Config{
		port    = config.Server_Port,
		db_type = .MySQL,
		secret  = config.App_Secret,
	})

	// Middleware ("runes"), registered onion-style, outermost first.
	gh.rune(&app, gh.logger)
	gh.rune(&app, middleware.admin_auth)

	global.conn = db.init()
	defer db.close(global.conn)

	env := jinja.create_environment({
		autoescape = true, 
		loader = jinja.filesystem_loader({config.View_Path}),
	})
	global.view = &env
	defer jinja.destroy_environment(global.view)

	view.add_functions()

	app_router.route(&app)

	log.info("Listening on http://localhost:6969")

	gh.run(&app)
}
