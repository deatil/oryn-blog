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

	// profile
	gh.get(app, "/admin/profile", admin.profile_index)
	gh.post(app, "/admin/profile/info", admin.profile_info_save)
	gh.post(app, "/admin/profile/password", admin.profile_password_save)

	// cate
	gh.get(app, "/admin/cate", admin.cate_index)
	gh.get(app, "/admin/cate/data", admin.cate_data)
	gh.get(app, "/admin/cate/create", admin.cate_create)
	gh.post(app, "/admin/cate/create", admin.cate_create_save)
	gh.get(app, "/admin/cate/edit", admin.cate_edit)
	gh.post(app, "/admin/cate/edit", admin.cate_edit_save)
	gh.post(app, "/admin/cate/del", admin.cate_del)

	// art
	gh.get(app, "/admin/art", admin.art_index)
	gh.get(app, "/admin/art/data", admin.art_data)
	gh.get(app, "/admin/art/create", admin.art_create)
	gh.post(app, "/admin/art/create", admin.art_create_save)
	gh.get(app, "/admin/art/edit", admin.art_edit)
	gh.post(app, "/admin/art/edit", admin.art_edit_save)
	gh.post(app, "/admin/art/del", admin.art_del)

	// comment
	gh.get(app, "/admin/comment", admin.comment_index)
	gh.get(app, "/admin/comment/data", admin.comment_data)
	gh.get(app, "/admin/comment/view", admin.comment_view)
	gh.post(app, "/admin/comment/del", admin.comment_del)

	// setting
	gh.get(app, "/admin/setting", admin.setting_index)
	gh.post(app, "/admin/setting", admin.setting_save)
}
