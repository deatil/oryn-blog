package admin

import "core:fmt"
import "core:time"
import "core:math"
import "core:strconv"
import "core:encoding/json"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/utils"

art_index :: proc(b: ^gh.Bifrost) {
	count := model.get_art_count()

	data := jinja.dict()
	jinja.set(data, "count", count)

	output, _ := view.render("admin/art/index.html", data)

	view.return_html(b, output)
}

art_data :: proc(b: ^gh.Bifrost) {
	page, _ := gh.query_param(b, "page")
	limit, _ := gh.query_param(b, "limit")
	keywords, _ := gh.query_param(b, "keywords")

	if len(page) == 0 {
		page = "1"
	}
	new_page, _ := strconv.parse_int(page)
	new_page = math.max(1, new_page)

	if len(limit) == 0 {
		limit = "10"
	}
	new_limit, _ := strconv.parse_int(limit)
	new_limit = math.max(1, new_limit)

	lists := model.get_arts(model.Art_Where{
		offset = (new_page - 1) * 10,
        limit = new_limit,
        keywords = keywords,
		status = -1,
	})

	count := model.get_art_count()

	list := make(json.Array)
	for i := 0; i < len(lists); i += 1 {
		d := make(json.Object)
		for k, v in lists[i] {
			d[k] = json.String(v)
		}
		append(&list, json.Value(d))
	}

	data := make(json.Object)
	data["count"] = json.String(count)
	data["list"] = list

	view.return_success(b, "获取成功", data)
}

art_create :: proc(b: ^gh.Bifrost) {
	cate_list := model.get_cate_all2()

	cates := jinja.list()
	for item in cate_list {
		d := jinja.dict()
		jinja.set(d, "id", jinja.str(item["id"]))
		jinja.set(d, "name", jinja.str(item["name"]))

		jinja.append_value(cates, d)
	}

	data := jinja.dict()
	jinja.set(data, "cates", cates)
	
	output, _ := view.render("admin/art/create.html", data)

	view.return_html(b, output)
}

art_create_save :: proc(b: ^gh.Bifrost) {
	fields := gh.form(b)

	title := fields["title"]
	if title == "" {
		view.return_error(b, "标题不能为空")
		return
	}
	cate_id := fields["cate_id"]
	if cate_id == "" {
		view.return_error(b, "分类不能为空")
		return
	}

	user_name, _ := auth.user_current_user(b)
	user_info := model.get_user(user_name)

	data := make(map[string]string)
	data["cate_id"] = cate_id
	data["user_id"] = user_info["id"]
	data["title"] = title
	data["status"] = "0"
	data["add_time"] = fmt.tprintf("%v", time.time_to_unix(time.now()))
	data["add_ip"] = gh.client_ip(b)

	if !model.add_art(data) {
		view.return_error(b, "添加失败")
		return
	}

	view.return_success(b, "添加成功")
}

art_edit :: proc(b: ^gh.Bifrost) {
	id, _ := gh.query_param(b, "id")
	item := model.get_art(id)

	ctx := jinja.dict()
	jinja.set(ctx, "id", jinja.str(item["id"]))
	jinja.set(ctx, "cate_id", jinja.str(item["cate_id"]))
	jinja.set(ctx, "title", jinja.str(item["title"]))
	jinja.set(ctx, "keywords", jinja.str(item["keywords"]))
	jinja.set(ctx, "description", jinja.str(item["description"]))
	jinja.set(ctx, "content", jinja.str(item["content"]))
	jinja.set(ctx, "tags", jinja.str(item["tags"]))
	jinja.set(ctx, "from", jinja.str(item["from"]))
	jinja.set(ctx, "views", jinja.str(item["views"]))
	jinja.set(ctx, "is_top", jinja.str(item["is_top"]))
	jinja.set(ctx, "status", jinja.str(item["status"]))

	cate_list := model.get_cate_all2()

	cates := jinja.list()
	for item in cate_list {
		d := jinja.dict()
		jinja.set(d, "id", jinja.str(item["id"]))
		jinja.set(d, "name", jinja.str(item["name"]))

		jinja.append_value(cates, d)
	}

	data := jinja.dict()
	jinja.set(data, "data", ctx)
	jinja.set(data, "cates", cates)

	output, _ := view.render("admin/art/edit.html", data)

	view.return_html(b, output)
}

art_edit_save :: proc(b: ^gh.Bifrost) {
	id, ok := gh.query_param(b, "id")
	if !ok {
		view.return_error(b, "ID不能为空")
		return
	}

	fields := gh.form(b)

	title := fields["title"]
	if title == "" {
		view.return_error(b, "标题不能为空")
		return
	}
	cate_id := fields["cate_id"]
	if cate_id == "" {
		view.return_error(b, "分类不能为空")
		return
	}

	data := make(map[string]string)
	data["cate_id"] = cate_id
	data["title"] = title
	data["keywords"] = fields["keywords"]
	data["description"] = fields["description"]
	data["content"] = fields["content"]
	data["tags"] = fields["tags"]
	data["from"] = fields["from"]
	data["views"] = fields["views"]
	data["is_top"] = fields["is_top"]
	data["status"] = fields["status"]

	if !model.update_art(id, data) {
		view.return_error(b, "修改失败")
		return
	}

	view.return_success(b, "修改成功")
}

art_del :: proc(b: ^gh.Bifrost) {
	id, ok := gh.query_param(b, "id")
	if !ok {
		view.return_error(b, "ID不能为空")
		return
	}

	if !model.delete_art(id) {
		view.return_error(b, "删除失败")
		return
	}

	view.return_success(b, "删除成功")
}
