package admin

import "core:fmt"
import "core:time"
import "core:encoding/json"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/utils"

cate_index :: proc(b: ^gh.Bifrost) {
	count := model.get_cate_count()

	data := jinja.dict()
	jinja.set(data, "count", count)
	
	output, _ := view.render("admin/cate/index.html", data)

	view.return_html(b, output)
}

cate_data :: proc(b: ^gh.Bifrost) {
	start := gh.param_int(b, "start")

	list := model.get_cates(model.Cate_Where{
		offset = start
	})

	data := json.Array
	for k, v in list {
		data[k] = json.Object(v)
	}

	view.return_success(b, "获取成功", data)
}

cate_create :: proc(b: ^gh.Bifrost) {
	data := jinja.dict()	
	output, _ := view.render("admin/cate/create.html", data)

	view.return_html(b, output)
}

cate_create_save :: proc(b: ^gh.Bifrost) {
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
