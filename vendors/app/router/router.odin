package router

import "vendors:http"
import "vendors:app/controller"

route :: proc(router: ^http.Router) {
	http.route_get(router, "/", http.handler(controller.index))
	http.route_get(router, "/view/(%d+)", http.handler(controller.view))

	http.route_get(router, "/edit/(%d+)", http.handler(controller.edit))
	http.route_post(router, "/edit/(%d+)", http.handler(controller.edit_save))

	http.route_get(router, "/add", http.handler(controller.add))
	http.route_post(router, "/add", http.handler(controller.add_save))

	http.route_get(router, "/del/(%d+)", http.handler(controller.del))

	// static
	http.route_get(router, "(.*)", http.handler(controller.static))
}
