package admin

import "core:fmt"
import "core:time"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/utils"

profile_index :: proc(b: ^gh.Bifrost) {
	username, _ := auth.user_current_user(b)

	data := jinja.dict()
	jinja.set(data, "username", username)
	
	output, _ := view.render("admin/profile/index.html", data)

	view.return_html(b, output)
}

profile_info_save :: proc(b: ^gh.Bifrost) {
	fields := gh.form(b)

	username := fields["username"]
	if username == "" {
		view.return_error(b, "新账号不能为空")
		return
	}

	user_name, _ := auth.user_current_user(b)
	user_info := model.get_user(user_name)

	data := make(map[string]string)
	data["username"] = username

	if !model.update_user(user_info["id"], data) {
		view.return_error(b, "修改失败")
		return
	}

	view.return_success(b, "修改成功")
}

profile_password_save :: proc(b: ^gh.Bifrost) {
	fields := gh.form(b)

	old_password := fields["old_password"]
	new_password := fields["new_password"]
	new_password2 := fields["new_password2"]

	if old_password == "" {
		view.return_error(b, "旧密码不能为空")
		return
	}
	if new_password == "" {
		view.return_error(b, "新密码不能为空")
		return
	}

	if new_password != new_password2 {
		view.return_error(b, "两次新密码不一致")
		return
	}

	username, _ := auth.user_current_user(b)
	info := model.get_user(username)

	if !utils.verify_password(old_password, info["password"]) {
		view.return_error(b, "旧密码错误")
		return
	}

	pass, ok := utils.hash_password(new_password)
	if !ok {
		view.return_error(b, "更改密码失败")
		return
	}

	data := make(map[string]string)
	data["password"] = pass

	if !model.update_user(info["id"], data) {
		view.return_error(b, "修改密码失败")
		return
	}

	view.return_success(b, "修改密码成功")
}
