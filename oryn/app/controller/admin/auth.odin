package admin

import "core:fmt"
import "core:time"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/utils"

auth_login :: proc(b: ^gh.Bifrost) {
	ok := auth.admin_require_login(b)
	if ok {
		view.redirect(b, "/admin/index")
		return;
	}

	data := jinja.dict()
	output, _ := view.render("admin/auth/login.html", data)

	view.return_html(b, output)
}

auth_login_save :: proc(b: ^gh.Bifrost) {
	fields := gh.form(b)

	username := fields["username"]
	password := fields["password"]

	info := model.get_admin(username)
	if len(info) == 0 {
		view.return_error(b, "登陆失败")
		return
	}

	if !utils.verify_password(password, info["password"]) {
		view.return_error(b, "登陆失败")
		return
	}

	auth.admin_login(b, username)

	view.return_success(b, "登陆成功")
}

auth_logout :: proc(b: ^gh.Bifrost) {
	auth.admin_logout(b)
	view.redirect(b, "/admin/auth/login")
}
