package router

import "oryn:http"
import "oryn:app/controller"
import admin_controller "oryn:app/controller/admin"

route :: proc(router: ^http.Router) {
	http.route_get(router, "/", http.handler(controller.index))
	http.route_get(router, "/view/(%d+)", http.handler(controller.view))

	http.route_get(router, "/edit/(%d+)", http.handler(controller.edit))
	http.route_post(router, "/edit/(%d+)", http.handler(controller.edit_save))

	http.route_get(router, "/add", http.handler(controller.add))
	http.route_post(router, "/add", http.handler(controller.add_save))

	http.route_get(router, "/del/(%d+)", http.handler(controller.del))

	admin_route(router)

	// static
	http.route_get(router, "(.*)", http.handler(controller.static))
}

admin_route :: proc(router: ^http.Router) {
	http.route_get(router, "/admin/auth/login", http.handler(admin_controller.auth_login))
	http.route_post(router, "/admin/auth/login", http.handler(admin_controller.auth_login_save))
}
