package router

import "vendors:http"
import "vendors:app/controller"

route :: proc(router: ^http.Router) {
	http.route_get(router, "/", http.handler(controller.index))
	http.route_get(router, "/view/(%d+)", http.handler(controller.view))

	// static
	http.route_get(router, "(.*)", http.handler(controller.static))
}
