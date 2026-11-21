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

comment_index :: proc(b: ^gh.Bifrost) {
	count := model.get_comment_count()

	data := jinja.dict()
	jinja.set(data, "count", count)
	
	output, _ := view.render("admin/comment/index.html", data)

	view.return_html(b, output)
}

comment_data :: proc(b: ^gh.Bifrost) {
	page, _ := gh.query_param(b, "page")
	limit, _ := gh.query_param(b, "limit")

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

	lists := model.get_comments(model.Comment_Where{
		offset = (new_page - 1) * 10,
        limit = new_limit,
		status = -1,
	})

	count := model.get_comment_count()

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

comment_view :: proc(b: ^gh.Bifrost) {
	id, _ := gh.query_param(b, "id")
	item := model.get_comment(id)

	ctx := jinja.dict()
	jinja.set(ctx, "id", jinja.str(item["id"]))
	jinja.set(ctx, "art_id", jinja.str(item["art_id"]))
	jinja.set(ctx, "content", jinja.str(item["content"]))
	jinja.set(ctx, "username", jinja.str(item["username"]))
	jinja.set(ctx, "status", jinja.str(item["status"]))

	art_info := model.get_art(item["art_id"])

	art := jinja.dict()
	jinja.set(art, "id", jinja.str(art_info["id"]))
	jinja.set(art, "title", jinja.str(art_info["title"]))

	data := jinja.dict()
	jinja.set(data, "data", ctx)
	jinja.set(data, "art", art)

	output, _ := view.render("admin/comment/view.html", data)

	view.return_html(b, output)
}

comment_del :: proc(b: ^gh.Bifrost) {
	id, ok := gh.query_param(b, "id")
	if !ok {
		view.return_error(b, "ID不能为空")
		return
	}

	if !model.delete_comment(id) {
		view.return_error(b, "删除失败")
		return
	}

	view.return_success(b, "删除成功")
}
