package main

import "core:fmt"
import "core:log"
import "core:net"

import "oryn:http"
import "oryn:jinja"

import "oryn:app/db"
import "oryn:app/config"
import "oryn:app/global"
import "oryn:app/view"
import app_router "oryn:app/router"

// run test:
// > odin run . -collection:oryn=oryn
main :: proc() {
	context.logger = log.create_console_logger(.Info)

	s: http.Server
	// Register a graceful shutdown when the program receives a SIGINT signal.
	http.server_shutdown_on_interrupt(&s)

	// Set up routing
	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	global.conn = db.init()
	defer db.close(global.conn)

    env := jinja.create_environment({
		autoescape = true, 
		loader = jinja.filesystem_loader({config.View_Path}),
	})
	global.view = &env
    defer jinja.destroy_environment(global.view)

	view.add_functions()

	app_router.route(&router)

	routed := http.router_handler(&router)

	log.info("Listening on http://localhost:6969")

	err := http.listen_and_serve(&s, routed, net.Endpoint{
		address = net.IP4_Loopback, 
		port = config.Server_Port,
	})

	fmt.assertf(err == nil, "server stopped with error: %v", err)
}
