package main

import "core:fmt"
import "core:log"
import "core:net"

import "vendors:http"
import "vendors:app/config"
import app_router "vendors:app/router"

// odin run . -collection:vendors=vendors
main :: proc() {
	context.logger = log.create_console_logger(.Info)

	s: http.Server
	// Register a graceful shutdown when the program receives a SIGINT signal.
	http.server_shutdown_on_interrupt(&s)

	// Set up routing
	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	app_router.route(&router)

	routed := http.router_handler(&router)

	log.info("Listening on http://localhost:6969")

	err := http.listen_and_serve(&s, routed, net.Endpoint{address = net.IP4_Loopback, port = config.Server_Port})
	fmt.assertf(err == nil, "server stopped with error: %v", err)
}
