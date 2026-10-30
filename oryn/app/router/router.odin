package router

import gh "oryn:gjallarhorn"

import "oryn:app/config"
import admin "oryn:app/controller/admin"

route :: proc(app: ^gh.App) {
	admin_route(app)

	gh.hail(app, "/static", config.Static_Path)
}

admin_route :: proc(app: ^gh.App) {
	gh.get(app, "/admin/index", admin.index_index)
	gh.get(app, "/admin/console", admin.index_console)
	gh.get(app, "/admin/menus", admin.index_menus)

	// auth
	gh.get(app, "/admin/auth/login", admin.auth_login)
	gh.post(app, "/admin/auth/login", admin.auth_login_save)
	gh.get(app, "/admin/auth/logout", admin.auth_logout)
}
